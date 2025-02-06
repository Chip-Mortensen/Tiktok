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
require('dotenv').config();

ffmpeg.setFfmpegPath(ffmpegInstaller.path);

exports.transcribeAndSegmentAudio = functions.storage.onObjectFinalized(
  {
    timeoutSeconds: 540,
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

      // Transcribe using Whisper API
      console.log('🎙️ Starting transcription with Whisper API...');
      const audioStream = fs.createReadStream(tempAudioPath);
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
        throw new Error('Transcription failed');
      }

      const whisperResult = await whisperResponse.json();
      console.log('✅ Transcription complete:', {
        transcriptionLength: whisperResult.text.length,
        preview: whisperResult.text.substring(0, 100) + '...',
        wordCount: whisperResult.words?.length || 0,
        firstFewWords: whisperResult.words?.slice(0, 3),
      });

      // Segment with GPT-4o-mini
      console.log('🧠 Starting segmentation with GPT-4o-mini...');
      const segmentationPayload = {
        model: 'gpt-4o-mini',
        messages: [
          {
            role: 'system',
            content: `You are a video segmentation AI. Given the full transcript below with word-level timestamps, extract major topical segments and identify filler content. The video is ${Math.round(
              duration
            )} seconds long. Use the word timestamps to create accurate segment boundaries.

Filler content includes:
- Repetitive or redundant explanations
- Off-topic tangents
- Excessive introductions or outros
- "Um"s, "Ah"s, and verbal pauses
- Unnecessary small talk
- Content that doesn't contribute to the main message

Transcript format includes word-level timing:
${JSON.stringify(whisperResult.words?.slice(0, 3), null, 2)}
...and so on.

Create segments that align with the natural topic changes in the content, using the word timestamps to set precise segment boundaries. Mark segments as filler when they match the criteria above.`,
          },
          {
            role: 'user',
            content: `Full transcript: ${whisperResult.text}\n\nWord timestamps: ${JSON.stringify(whisperResult.words)}`,
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

      const segmentationResponse = await fetch('https://api.openai.com/v1/chat/completions', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${process.env.OPENAI_API_KEY}`,
        },
        body: JSON.stringify(segmentationPayload),
      });

      console.log('📡 GPT-4o-mini response status:', segmentationResponse.status);

      const responseText = await segmentationResponse.text();
      console.log('📝 Raw GPT-4o-mini response:', responseText);

      if (!segmentationResponse.ok) {
        console.error('❌ GPT-4o-mini API error:', responseText);
        throw new Error('Segmentation failed');
      }

      const segmentationResult = JSON.parse(responseText);
      console.log('🔍 Parsed GPT-4o-mini result:', JSON.stringify(segmentationResult, null, 2));

      if (!segmentationResult.choices?.[0]?.message?.content) {
        console.error('❌ Unexpected response structure:', segmentationResult);
        throw new Error('Unexpected response structure from GPT-4o-mini');
      }

      const contentJson = JSON.parse(segmentationResult.choices[0].message.content);
      const segments = contentJson.segments;

      if (!segments) {
        console.error('❌ No segments in parsed content:', contentJson);
        throw new Error('No segments found in GPT-4o-mini response');
      }

      console.log('✅ Segmentation complete:', {
        numberOfSegments: segments.length,
        segments: segments,
      });

      // Update Firestore
      console.log('💾 Updating Firestore...');
      await firestore.collection('videos').doc(videoId).update({
        transcription: whisperResult.text,
        segments: segments,
        processedAt: FieldValue.serverTimestamp(),
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
