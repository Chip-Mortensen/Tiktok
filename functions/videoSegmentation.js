const { getFirestore, FieldValue } = require('firebase-admin/firestore');
const { getStorage } = require('firebase-admin/storage');
const functions = require('firebase-functions/v2');
const ffmpeg = require('fluent-ffmpeg');
const ffmpegInstaller = require('@ffmpeg-installer/ffmpeg');
const os = require('os');
const path = require('path');
const fs = require('fs');
const fetch = require('node-fetch');
const FormData = require('form-data');
const { encode } = require('gpt-3-encoder');

ffmpeg.setFfmpegPath(ffmpegInstaller.path);

// Add these helper functions before the main export
async function splitAudioIntoChunks(inputPath, chunkDuration = 600) {
  const chunks = [];
  const tmpDir = os.tmpdir();

  // Get total duration
  const duration = await new Promise((resolve, reject) => {
    ffmpeg.ffprobe(inputPath, (err, metadata) => {
      if (err) reject(err);
      resolve(metadata.format.duration);
    });
  });

  const numChunks = Math.ceil(duration / chunkDuration);
  console.log(`🔪 Splitting ${Math.round(duration)}s audio into ${numChunks} chunks of ${chunkDuration}s each`);

  for (let i = 0; i < numChunks; i++) {
    const start = i * chunkDuration;
    const outputPath = path.join(tmpDir, `chunk_${i}.mp3`);

    await new Promise((resolve, reject) => {
      ffmpeg(inputPath)
        .setStartTime(start)
        .setDuration(Math.min(chunkDuration, duration - start))
        .output(outputPath)
        .on('end', resolve)
        .on('error', reject)
        .run();
    });

    chunks.push({
      path: outputPath,
      startTime: start,
    });
  }

  return chunks;
}

async function transcribeAudioChunk(chunkPath, startTime) {
  const audioStream = fs.createReadStream(chunkPath);
  const formData = new FormData();
  formData.append('file', audioStream);
  formData.append('model', 'whisper-1');
  formData.append('response_format', 'verbose_json');
  formData.append('timestamp_granularities[]', 'word');

  const whisperResponse = await fetch('https://api.openai.com/v1/audio/transcriptions', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${process.env.OPENAI_API_KEY}`,
    },
    body: formData,
  });

  if (!whisperResponse.ok) {
    const errorText = await whisperResponse.text();
    console.error('❌ Whisper API error:', errorText);
    throw new Error(`Transcription failed for chunk starting at ${startTime}s`);
  }

  const result = await whisperResponse.json();

  // Adjust timestamps to account for chunk position
  if (result.words) {
    result.words = result.words.map((word) => ({
      ...word,
      start: word.start + startTime,
      end: word.end + startTime,
    }));
  }

  return result;
}

async function createSlidingWindows(text, words, maxTokens = 100000, overlapTokens = 20000) {
  const getTokenCount = (text) => encode(text).length;

  try {
    // Calculate fixed overhead
    const systemPrompt = `You are a video segmentation AI. Given the transcript below with word-level timestamps, extract major topical segments and identify filler content. This is a portion of a X second video, from Y to Z. Use the word timestamps to create accurate segment boundaries.

Filler content includes:
- Repetitive or redundant explanations
- Off-topic tangents
- Excessive introductions or outros
- "Um"s, "Ah"s, and verbal pauses
- Unnecessary small talk
- Content that doesn't contribute to the main message`;

    const SCHEMA_TOKENS = 70;
    const SYSTEM_PROMPT_TOKENS = getTokenCount(systemPrompt);
    const JSON_STRUCTURE_TOKENS = 100;
    const SAFETY_MARGIN = 1000;
    const BASE_OVERHEAD = SYSTEM_PROMPT_TOKENS + SCHEMA_TOKENS + JSON_STRUCTURE_TOKENS + SAFETY_MARGIN;

    // Calculate per-word token overhead for timestamps JSON structure
    const sampleTimestamps = JSON.stringify([
      {
        word: words[0].word,
        start: words[0].start,
        end: words[0].end,
      },
    ]);
    const TOKENS_PER_TIMESTAMP = getTokenCount(sampleTimestamps) / 1;

    // Target size calculation
    const TARGET_WINDOW_SIZE = Math.floor((maxTokens - BASE_OVERHEAD) * 0.4); // Use 40% for text
    const MAX_WORDS_PER_WINDOW = Math.floor(TARGET_WINDOW_SIZE / (1 + TOKENS_PER_TIMESTAMP));

    console.log(`Token budget analysis:
      Max tokens: ${maxTokens}
      Base overhead: ${BASE_OVERHEAD}
      Tokens per timestamp: ${TOKENS_PER_TIMESTAMP}
      Target window size: ${TARGET_WINDOW_SIZE}
      Max words per window: ${MAX_WORDS_PER_WINDOW}
    `);

    const windows = [];
    let startIndex = 0;

    while (startIndex < words.length) {
      // Calculate how many words we can include
      const remainingWords = words.length - startIndex;
      const windowWordCount = Math.min(MAX_WORDS_PER_WINDOW, remainingWords);

      if (windowWordCount < 10) {
        console.log('Remaining words too few, extending last window');
        if (windows.length > 0) {
          const lastWindow = windows[windows.length - 1];
          lastWindow.words = lastWindow.words.concat(words.slice(startIndex));
          lastWindow.text = lastWindow.words.map((w) => w.word).join(' ');
          lastWindow.endTime = words[words.length - 1].end;
        }
        break;
      }

      // Create window
      const windowWords = words.slice(startIndex, startIndex + windowWordCount);
      const windowText = windowWords.map((w) => w.word).join(' ');

      // Verify token count
      const timestampTokens = windowWords.length * TOKENS_PER_TIMESTAMP;
      const textTokens = getTokenCount(windowText);
      const totalTokens = textTokens + timestampTokens + BASE_OVERHEAD;

      console.log(`Window size verification:
        Words: ${windowWords.length}
        Text tokens: ${textTokens}
        Timestamp tokens: ${timestampTokens}
        Total tokens: ${totalTokens}
        Limit: ${maxTokens}
      `);

      if (totalTokens > maxTokens) {
        throw new Error(`Window exceeds token limit: ${totalTokens} > ${maxTokens}. This should not happen!`);
      }

      windows.push({
        text: windowText,
        words: windowWords,
        startTime: windowWords[0].start,
        endTime: windowWords[windowWords.length - 1].end,
      });

      // Calculate overlap
      const overlapWordCount = Math.min(
        Math.floor(windowWordCount * 0.15), // 15% overlap
        remainingWords - windowWordCount // Don't overlap beyond available words
      );

      // Advance to next window
      startIndex += windowWordCount - overlapWordCount;
    }

    // Verify windows
    console.log(`📊 Created ${windows.length} windows`);
    windows.forEach((w, i) => {
      const timestampTokens = w.words.length * TOKENS_PER_TIMESTAMP;
      const textTokens = getTokenCount(w.text);
      const totalTokens = textTokens + timestampTokens + BASE_OVERHEAD;
      console.log(`Window ${i + 1}: ${Math.round(w.startTime)}s-${Math.round(w.endTime)}s, ${totalTokens} tokens, ${w.words.length} words`);

      // Verify no gaps between windows
      if (i > 0) {
        const gap = w.startTime - windows[i - 1].endTime;
        if (gap > 1) {
          // 1 second tolerance
          console.warn(`⚠️ Gap detected between windows ${i} and ${i + 1}: ${gap}s`);
        }
      }
    });

    return windows;
  } catch (error) {
    console.error('Error creating windows:', error);
    throw error;
  }
}

// Add segment validation function
function validateSegments(segments, startTime, endTime) {
  return segments.filter((segment) => {
    // Check if timestamps are numbers and within bounds
    if (typeof segment.startTime !== 'number' || typeof segment.endTime !== 'number') {
      console.warn('❌ Invalid segment timestamps:', segment);
      return false;
    }
    if (segment.startTime < startTime || segment.endTime > endTime) {
      console.warn('❌ Segment out of bounds:', segment);
      return false;
    }
    if (segment.startTime >= segment.endTime) {
      console.warn('❌ Invalid segment duration:', segment);
      return false;
    }
    return true;
  });
}

async function segmentWindow(window, totalDuration, maxRetries = 3) {
  const delay = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
  let lastError = null;

  for (let attempt = 1; attempt <= maxRetries; attempt++) {
    try {
      const segmentationPayload = {
        model: 'gpt-4o-mini',
        messages: [
          {
            role: 'system',
            content: `You are a video segmentation AI. Given the transcript below with word-level timestamps, extract major topical segments and identify filler content. This is a portion of a ${Math.round(
              totalDuration
            )} second video, from ${Math.round(window.startTime)}s to ${Math.round(
              window.endTime
            )}s. Use the word timestamps to create accurate segment boundaries.

Filler content includes:
- Repetitive or redundant explanations
- Off-topic tangents
- Excessive introductions or outros
- "Um"s, "Ah"s, and verbal pauses
- Unnecessary small talk
- Content that doesn't contribute to the main message`,
          },
          {
            role: 'user',
            content: `Transcript portion: ${window.text}\n\nWord timestamps: ${JSON.stringify(window.words)}`,
          },
        ],
        response_format: {
          type: 'json_schema',
          json_schema: {
            name: 'chunkedTopics',
            schema: {
              type: 'object',
              properties: {
                segments: {
                  type: 'array',
                  items: {
                    type: 'object',
                    properties: {
                      startTime: { type: 'number' },
                      endTime: { type: 'number' },
                      topic: { type: 'string' },
                      summary: { type: 'string' },
                      isFiller: { type: 'boolean' },
                    },
                    required: ['startTime', 'endTime', 'topic', 'summary', 'isFiller'],
                    additionalProperties: false,
                  },
                },
              },
              required: ['segments'],
              additionalProperties: false,
            },
            strict: true,
          },
        },
      };

      const response = await fetch('https://api.openai.com/v1/chat/completions', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${process.env.OPENAI_API_KEY}`,
        },
        body: JSON.stringify(segmentationPayload),
      });

      if (!response.ok) {
        const errorText = await response.text();
        if (response.status === 429 || response.status >= 500) {
          console.log(`Attempt ${attempt}: Rate limit or server error, retrying in ${attempt * 2}s...`);
          await delay(attempt * 2000);
          continue;
        }
        throw new Error(`Segmentation failed: ${errorText}`);
      }

      const result = await response.json();
      if (!result.choices?.[0]?.message?.content) {
        throw new Error('Invalid response format from GPT-4o-mini');
      }

      const segments = JSON.parse(result.choices[0].message.content).segments;
      if (!Array.isArray(segments)) {
        throw new Error('Invalid segments format in response');
      }

      // Validate segments
      const validSegments = validateSegments(segments, window.startTime, window.endTime);
      if (validSegments.length === 0) {
        throw new Error('No valid segments found in response');
      }
      if (validSegments.length < segments.length) {
        console.warn(`⚠️ Filtered out ${segments.length - validSegments.length} invalid segments`);
      }

      return validSegments;
    } catch (error) {
      lastError = error;
      if (attempt === maxRetries) {
        console.error(`All ${maxRetries} attempts failed for window ${Math.round(window.startTime)}s-${Math.round(window.endTime)}s`);
        throw lastError;
      }
      console.log(`Attempt ${attempt} failed, retrying in ${attempt * 2}s...`);
      await delay(attempt * 2000);
    }
  }

  // This should never be reached due to the throw above, but TypeScript will be happier
  throw lastError || new Error('Segmentation failed with no error details');
}

function mergeOverlappingSegments(allSegments) {
  if (allSegments.length === 0) return [];

  // Sort segments by start time
  const sorted = allSegments.sort((a, b) => a.startTime - b.startTime);
  const merged = [sorted[0]];

  for (let i = 1; i < sorted.length; i++) {
    const current = sorted[i];
    const previous = merged[merged.length - 1];

    // Check for overlap
    if (current.startTime <= previous.endTime + 2) {
      // 2-second tolerance
      // If topics are similar or one contains the other
      if (current.topic.includes(previous.topic) || previous.topic.includes(current.topic) || levenshteinDistance(current.topic, previous.topic) < 5) {
        // Merge segments
        previous.endTime = Math.max(previous.endTime, current.endTime);
        previous.summary = previous.summary + ' ' + current.summary;
        previous.isFiller = previous.isFiller && current.isFiller;
      } else {
        // Topics are different, adjust boundary to midpoint
        const midpoint = (previous.endTime + current.startTime) / 2;
        previous.endTime = midpoint;
        current.startTime = midpoint;
        merged.push(current);
      }
    } else {
      merged.push(current);
    }
  }

  return merged;
}

function levenshteinDistance(str1, str2) {
  const m = str1.length;
  const n = str2.length;
  const dp = Array(m + 1)
    .fill()
    .map(() => Array(n + 1).fill(0));

  for (let i = 0; i <= m; i++) dp[i][0] = i;
  for (let j = 0; j <= n; j++) dp[0][j] = j;

  for (let i = 1; i <= m; i++) {
    for (let j = 1; j <= n; j++) {
      if (str1[i - 1] === str2[j - 1]) {
        dp[i][j] = dp[i - 1][j - 1];
      } else {
        dp[i][j] = Math.min(dp[i - 1][j - 1] + 1, dp[i - 1][j] + 1, dp[i][j - 1] + 1);
      }
    }
  }

  return dp[m][n];
}

exports.transcribeAndSegmentAudio = functions.storage.onObjectFinalized(
  {
    timeoutSeconds: 1800,
    memory: '2GB',
    secrets: ['OPENAI_API_KEY'],
  },
  async (event) => {
    const firestore = getFirestore();
    const storage = getStorage();

    const object = event.data;
    console.log('🎥 Starting video processing...', { objectName: object.name, contentType: object.contentType });

    // Validate incoming file
    if (!object.name.startsWith('videos/') || !object.contentType.startsWith('video/')) {
      console.log('⚠️ Skipping non-video file:', object.name);
      return null;
    }

    const bucketName = object.bucket;
    const filePath = object.name;
    const fileName = path.basename(filePath);
    const videoId = path.parse(fileName).name;
    const tmpDir = os.tmpdir();
    const tempVideoPath = path.join(tmpDir, fileName);
    const audioFileName = `${videoId}.mp3`;
    const tempAudioPath = path.join(tmpDir, audioFileName);

    console.log('📁 File details:', {
      bucketName,
      filePath,
      videoId,
      tempVideoPath,
      tempAudioPath,
    });

    try {
      // Download video file locally
      console.log('⬇️ Downloading video file...');
      await storage.bucket(bucketName).file(filePath).download({ destination: tempVideoPath });
      console.log('✅ Video downloaded successfully to:', tempVideoPath);

      // Get video duration
      console.log('⏱️ Getting video duration...');
      const duration = await new Promise((resolve, reject) => {
        ffmpeg.ffprobe(tempVideoPath, (err, metadata) => {
          if (err) {
            console.error('❌ Error getting duration:', err);
            reject(err);
          }
          resolve(metadata.format.duration);
        });
      });
      console.log('📊 Video duration:', duration, 'seconds');

      // Extract audio as MP3
      console.log('🎵 Extracting audio...');
      await new Promise((resolve, reject) => {
        ffmpeg(tempVideoPath)
          .noVideo()
          .audioCodec('libmp3lame')
          .audioQuality(2)
          .on('start', (commandLine) => {
            console.log('🎬 FFmpeg command:', commandLine);
          })
          .on('progress', (progress) => {
            console.log('⏳ Processing:', progress.percent, '% done');
          })
          .on('end', () => {
            console.log('✅ Audio extraction complete');
            resolve();
          })
          .on('error', (err) => {
            console.error('❌ FFmpeg error:', err);
            reject(err);
          })
          .save(tempAudioPath);
      });

      // Replace the single transcription call with chunked processing
      console.log('🎙️ Starting chunked transcription with Whisper API...');
      const chunks = await splitAudioIntoChunks(tempAudioPath);

      let allWords = [];
      let fullTranscript = '';

      for (let i = 0; i < chunks.length; i++) {
        const chunk = chunks[i];
        console.log(`📝 Transcribing chunk ${i + 1}/${chunks.length} (starts at ${chunk.startTime}s)`);

        const chunkResult = await transcribeAudioChunk(chunk.path, chunk.startTime);

        if (chunkResult.words) {
          allWords = allWords.concat(chunkResult.words);
        }
        fullTranscript += (i > 0 ? ' ' : '') + chunkResult.text;

        // Clean up chunk file
        fs.unlinkSync(chunk.path);
      }

      // Sort words by start time to ensure proper ordering
      allWords.sort((a, b) => a.start - b.start);

      const whisperResult = {
        text: fullTranscript,
        words: allWords,
      };

      console.log('✅ Transcription complete:', {
        transcriptionLength: whisperResult.text.length,
        preview: whisperResult.text.substring(0, 100) + '...',
        wordCount: whisperResult.words?.length || 0,
        firstFewWords: whisperResult.words?.slice(0, 3),
      });

      // Segment with sliding windows
      console.log('🧠 Starting sliding window segmentation...');
      const windows = await createSlidingWindows(whisperResult.text, whisperResult.words);
      console.log(`📊 Created ${windows.length} windows for processing`);

      let allSegments = [];
      let failedWindows = [];

      for (let i = 0; i < windows.length; i++) {
        const window = windows[i];
        console.log(`🎯 Processing window ${i + 1}/${windows.length} (${Math.round(window.startTime)}s-${Math.round(window.endTime)}s)`);

        try {
          const windowSegments = await segmentWindow(window, duration);
          allSegments = allSegments.concat(windowSegments);
          console.log(`✅ Window ${i + 1} complete: found ${windowSegments.length} segments`);

          // Clean up processed window to free memory
          window.words = null;
          window.text = null;
        } catch (error) {
          console.error(`❌ Failed to process window ${i + 1}:`, error);
          failedWindows.push({
            windowIndex: i,
            startTime: window.startTime,
            endTime: window.endTime,
            error: error.message,
          });
        }

        // Every 5 windows, merge segments to free up memory
        if (i > 0 && i % 5 === 0) {
          allSegments = mergeOverlappingSegments(allSegments);
        }
      }

      console.log('🔄 Final merge of all segments...');
      const segments = mergeOverlappingSegments(allSegments);

      // Clear large arrays to free memory
      allSegments = null;
      windows.forEach((w) => {
        w.words = null;
        w.text = null;
      });

      console.log('✅ Segmentation complete:', {
        numberOfSegments: segments.length,
        failedWindows: failedWindows.length > 0 ? failedWindows : 'none',
      });

      // Update Firestore with segments and processing metadata
      console.log('💾 Updating Firestore...');
      await firestore
        .collection('videos')
        .doc(videoId)
        .update({
          transcription: whisperResult.text,
          segments: segments,
          processedAt: FieldValue.serverTimestamp(),
          processingMetadata: {
            totalWindows: windows.length,
            failedWindows: failedWindows,
            segmentCount: segments.length,
          },
        });
      console.log('✅ Firestore updated successfully');

      // Cleanup
      console.log('🧹 Cleaning up temporary files...');
      fs.unlinkSync(tempVideoPath);
      fs.unlinkSync(tempAudioPath);
      console.log('✅ Temporary files cleaned up');

      return {
        success: true,
        videoId,
        segmentsCount: segments.length,
      };
    } catch (error) {
      console.error('❌ Error processing video:', error);

      // Cleanup on error
      try {
        if (fs.existsSync(tempVideoPath)) fs.unlinkSync(tempVideoPath);
        if (fs.existsSync(tempAudioPath)) fs.unlinkSync(tempAudioPath);
      } catch (cleanupError) {
        console.error('❌ Error during cleanup:', cleanupError);
      }

      throw error;
    }
  }
);
