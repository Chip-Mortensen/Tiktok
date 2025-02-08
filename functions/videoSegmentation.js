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

async function createSlidingWindows(text, words, maxTokens = 100000) {
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

      // Calculate overlap - use more overlap for better context
      const overlapWordCount = Math.min(
        Math.floor(windowWordCount * 0.3), // 30% overlap for better context
        remainingWords - windowWordCount
      );

      // Advance to next window
      startIndex += windowWordCount - overlapWordCount;
    }

    // Log window information
    console.log(`📊 Created ${windows.length} windows`);
    windows.forEach((w, i) => {
      console.log(`Window ${i + 1}: ${Math.round(w.startTime)}s-${Math.round(w.endTime)}s, ${w.words.length} words`);
    });

    return windows;
  } catch (error) {
    console.error('Error creating windows:', error);
    throw error;
  }
}

async function optimizeSegments(segments, totalDuration) {
  const optimizationPayload = {
    model: 'gpt-4o-mini',
    messages: [
      {
        role: 'system',
        content: `You are an expert at analyzing video content and creating meaningful, well-structured segments. Your task is to optimize these segments into cohesive, logical sections while maintaining precise timing.

Key Requirements:
1. Create end-to-end coverage with no gaps in timestamps
2. Combine segments that form part of a continuous discussion or theme
3. Handle advertisements and promotional content:
   - Maintain precise start/end times for ads
   - Keep them as separate segments
   - Mark them as filler content
4. Content Guidelines:
   - Group related consecutive topics into larger cohesive segments
   - Preserve natural topic flow and transitions
   - Keep contextual discussions together
   - Only split when there's a clear topic change
5. Filler Identification:
   - Mark as filler:
     * Advertisements and sponsorships
     * Self-promotion segments
     * Completely off-topic content
   - Do NOT mark as filler:
     * Topic transitions
     * Background context
     * Related examples or anecdotes
     * Casual conversation that adds value

The video is ${Math.round(
          totalDuration
        )} seconds long. You must create segments that cover the entire duration from 0 to ${totalDuration} seconds with no gaps or overlaps.`,
      },
      {
        role: 'user',
        content: `Please analyze and optimize these segments. Create cohesive sections while maintaining precise timing.

Current segments:
${JSON.stringify(segments, null, 2)}

Requirements:
1. Each segment must connect exactly to the next (endTime of one = startTime of next)
2. First segment must start at 0, last segment must end at ${totalDuration}
3. Maintain precise timestamps for advertisements
4. Combine related topics into larger, meaningful segments
5. Ensure natural content flow
6. Handle any overlapping segments by choosing the most appropriate boundaries

Return the optimized segments in the same JSON format.`,
      },
    ],
    response_format: {
      type: 'json_schema',
      json_schema: {
        name: 'optimizedSegments',
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

  try {
    const response = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${process.env.OPENAI_API_KEY}`,
      },
      body: JSON.stringify(optimizationPayload),
    });

    if (!response.ok) {
      throw new Error(`Optimization failed: ${await response.text()}`);
    }

    const result = await response.json();
    const optimizedSegments = JSON.parse(result.choices[0].message.content).segments;

    // Validate the optimized segments cover the full duration
    const firstSegment = optimizedSegments[0];
    const lastSegment = optimizedSegments[optimizedSegments.length - 1];

    if (!firstSegment || !lastSegment) {
      throw new Error('Optimization returned no segments');
    }

    if (firstSegment.startTime !== 0) {
      throw new Error(`First segment starts at ${firstSegment.startTime} instead of 0`);
    }

    if (Math.abs(lastSegment.endTime - totalDuration) > 1) {
      throw new Error(`Last segment ends at ${lastSegment.endTime} instead of ${totalDuration}`);
    }

    return optimizedSegments;
  } catch (error) {
    console.error('Error during segment optimization:', error);
    throw error; // Propagate the error instead of returning potentially invalid segments
  }
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

      // Process each window with the LLM directly
      for (let i = 0; i < windows.length; i++) {
        const window = windows[i];
        console.log(`🎯 Processing window ${i + 1}/${windows.length} (${Math.round(window.startTime)}s-${Math.round(window.endTime)}s)`);

        try {
          // Create initial segments for this window
          const segmentationPayload = {
            model: 'gpt-4o-mini',
            messages: [
              {
                role: 'system',
                content: `You are an expert at analyzing video content and creating meaningful segments. Your task is to break this transcript portion into logical segments while maintaining precise timing.

Key Requirements:
1. Create segments that capture complete thoughts or topics
2. Use natural breaks in conversation
3. Identify advertisements and promotional content precisely
4. Create segments that are neither too short nor too long
5. Mark as filler:
   - Clear advertisements and sponsorships
   - Self-promotion segments
   - Completely off-topic content

This is a portion of a ${Math.round(duration)} second video, from ${Math.round(window.startTime)}s to ${Math.round(window.endTime)}s.`,
              },
              {
                role: 'user',
                content: `Please analyze this transcript portion and create meaningful segments.

Transcript: ${window.text}

Word timestamps: ${JSON.stringify(window.words)}

Requirements:
1. Use the word timestamps to create precise segment boundaries
2. Each segment should have a clear topic and summary
3. Mark promotional content as filler
4. Ensure natural content flow

Return the segments in the required JSON format.`,
              },
            ],
            response_format: {
              type: 'json_schema',
              json_schema: {
                name: 'videoSegments',
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
            throw new Error(`Segmentation failed: ${await response.text()}`);
          }

          const result = await response.json();
          const windowSegments = JSON.parse(result.choices[0].message.content).segments;

          // Log segment information before adding to array
          console.log(
            `Window ${i + 1} segments:`,
            windowSegments.map((s) => ({
              start: Math.round(s.startTime),
              end: Math.round(s.endTime),
              topic: s.topic.substring(0, 50) + '...',
            }))
          );

          // Add segments to array and immediately clean up window
          allSegments = allSegments.concat(windowSegments);
          window.words = null;
          window.text = null;

          // Every 5 windows, log memory usage
          if (i % 5 === 0) {
            const used = process.memoryUsage();
            console.log('Memory usage:', {
              heapTotal: `${Math.round(used.heapTotal / 1024 / 1024)} MB`,
              heapUsed: `${Math.round(used.heapUsed / 1024 / 1024)} MB`,
              segments: allSegments.length,
            });
          }
        } catch (error) {
          console.error(`❌ Failed to process window ${i + 1}:`, error);
          failedWindows.push({
            windowIndex: i,
            startTime: window.startTime,
            endTime: window.endTime,
            error: error.message,
          });
        }
      }

      // Log failed windows
      if (failedWindows.length > 0) {
        console.warn('❌ Failed to process some windows:', failedWindows);
      }

      // Optimize segments
      console.log('🧠 Starting segment optimization...');
      const optimizedSegments = await optimizeSegments(allSegments, duration);
      console.log('✅ Segment optimization complete');

      // Save segments to Firestore
      console.log('💾 Updating Firestore...');
      await firestore
        .collection('videos')
        .doc(videoId)
        .update({
          transcription: whisperResult.text,
          segments: optimizedSegments,
          processedAt: FieldValue.serverTimestamp(),
          processingMetadata: {
            totalWindows: windows.length,
            failedWindows: failedWindows.length > 0 ? failedWindows : null,
            segmentCount: optimizedSegments.length,
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
        segmentsCount: optimizedSegments.length,
        failedWindows: failedWindows.length > 0 ? failedWindows : null,
      };
    } catch (error) {
      console.error('Error during video processing:', error);
      throw error;
    }
  }
);
