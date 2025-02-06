const { initializeApp } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const { getStorage } = require('firebase-admin/storage');
const { onObjectFinalized } = require('firebase-functions/v2/storage');
const { VideoIntelligenceServiceClient } = require('@google-cloud/video-intelligence');
const ffmpeg = require('fluent-ffmpeg');
const ffmpegInstaller = require('@ffmpeg-installer/ffmpeg');
const path = require('path');
const os = require('os');
const fs = require('fs');

initializeApp();
ffmpeg.setFfmpegPath(ffmpegInstaller.path);

exports.generateHLS = onObjectFinalized(
  {
    timeoutSeconds: 540,
    memory: '2GB',
    location: 'us-central1',
  },
  async (event) => {
    const object = event.data;
    console.log('Storage event received:', {
      name: object.name,
      contentType: object.contentType,
      size: object.size,
      timeCreated: object.timeCreated,
      updated: object.updated,
    });

    const isVideo = object.name.startsWith('videos/') && object.contentType.startsWith('video/');
    console.log('File validation:', {
      startsWithVideos: object.name.startsWith('videos/'),
      isVideoContentType: object.contentType.startsWith('video/'),
      isValidVideo: isVideo,
    });

    if (!isVideo) {
      console.log('Not a video in videos directory, skipping.');
      return null;
    }

    if (object.name.includes('hls/')) {
      console.log('This is an HLS file, skipping.');
      return null;
    }

    const fileBucket = object.bucket;
    const filePath = object.name;
    const fileName = path.basename(filePath);
    const videoId = path.parse(fileName).name;
    const userId = filePath.split('/')[1];
    const workingDir = path.join(os.tmpdir(), videoId);
    const hlsOutputDir = path.join(workingDir, 'hls');

    console.log('Processing video:', {
      fileBucket,
      filePath,
      fileName,
      videoId,
      userId,
      workingDir,
      hlsOutputDir,
    });

    try {
      console.log('Creating directories...');
      await fs.promises.mkdir(workingDir, { recursive: true });
      await fs.promises.mkdir(hlsOutputDir, { recursive: true });

      console.log('Downloading source video...');
      const bucket = getStorage().bucket(fileBucket);
      const tempInputPath = path.join(workingDir, fileName);
      await bucket.file(filePath).download({ destination: tempInputPath });
      console.log('Video downloaded successfully to:', tempInputPath);

      console.log('Starting FFmpeg conversion...');
      const hlsOutputPath = path.join(hlsOutputDir, 'playlist.m3u8');
      await new Promise((resolve, reject) => {
        ffmpeg(tempInputPath)
          .outputOptions([
            // Video settings
            '-c:v h264', // Use H.264 codec
            '-crf 23', // Constant Rate Factor (quality)
            '-preset fast', // Encoding speed preset
            '-profile:v main', // H.264 profile
            '-level:v 3.1', // H.264 level
            // Audio settings
            '-c:a aac', // Use AAC codec
            '-ar 48000', // Audio sample rate
            '-b:a 128k', // Audio bitrate
            // HLS specific settings
            '-start_number 0', // Start segment numbers from 0
            '-hls_time 4', // Shorter segments for faster initial playback
            '-hls_list_size 0', // Keep all segments
            '-hls_segment_type mpegts', // Use MPEG-TS segment format
            '-hls_flags delete_segments+independent_segments', // Independent segments for better seeking
            '-g 48', // Keyframe interval (GOP size)
            '-sc_threshold 0', // Disable scene change detection for consistent segments
            '-f hls', // Force HLS format
          ])
          .output(hlsOutputPath)
          .on('progress', (progress) => {
            console.log('FFmpeg progress:', progress);
          })
          .on('end', () => {
            console.log('FFmpeg conversion completed');
            resolve();
          })
          .on('error', (err) => {
            console.error('FFmpeg error:', err);
            reject(err);
          })
          .run();
      });

      console.log('Reading HLS directory...');
      const hlsFiles = await fs.promises.readdir(hlsOutputDir);
      console.log('HLS files generated:', hlsFiles);

      console.log('Uploading HLS files...');
      const uploadPromises = hlsFiles.map(async (filename) => {
        const sourcePath = path.join(hlsOutputDir, filename);
        const destinationPath = `hls/${userId}/${videoId}/${filename}`;
        const contentType = filename.endsWith('.m3u8') ? 'application/x-mpegURL' : 'video/MP2T';

        console.log('Uploading file:', { filename, destinationPath, contentType });
        await bucket.upload(sourcePath, {
          destination: destinationPath,
          metadata: { contentType },
        });
        return destinationPath;
      });

      await Promise.all(uploadPromises);
      console.log('All HLS files uploaded successfully');

      const m3u8File = `hls/${userId}/${videoId}/playlist.m3u8`;
      console.log('Getting public URL for:', m3u8File);
      const m3u8Url = `https://storage.googleapis.com/${fileBucket}/${m3u8File}`;

      console.log('Updating Firestore document...');
      const videoRef = getFirestore().collection('videos').doc(videoId);
      await videoRef.update({ m3u8Url });

      console.log('Cleaning up temporary files...');
      await fs.promises.rm(workingDir, { recursive: true, force: true });
      console.log('HLS generation completed successfully.');
      return null;
    } catch (error) {
      console.error('Error processing video:', error);
      console.error('Error details:', {
        message: error.message,
        stack: error.stack,
        code: error.code,
        details: error.details,
      });
      throw error;
    }
  }
);

// Helper function to convert time offset to seconds
function timeOffsetToSeconds(timeOffset) {
  if (!timeOffset) return 0;
  const seconds = Number(timeOffset.seconds || 0);
  const nanos = Number(timeOffset.nanos || 0);
  return seconds + nanos / 1000000000;
}

// Helper function to process video intelligence results
function processVideoResults(result) {
  const segments = [];
  console.log('Processing video analysis result:', JSON.stringify(result, null, 2));

  if (!result.annotationResults || !result.annotationResults[0]) {
    console.log('No annotation results found');
    return segments;
  }

  const annotations = result.annotationResults[0];

  // Process shot label annotations
  if (annotations.shotLabelAnnotations && annotations.shotLabelAnnotations.length > 0) {
    console.log('Found shot label annotations:', annotations.shotLabelAnnotations.length);
    for (const annotation of annotations.shotLabelAnnotations) {
      for (const segment of annotation.segments) {
        const startTime = timeOffsetToSeconds(segment.segment.startTimeOffset);
        const endTime = timeOffsetToSeconds(segment.segment.endTimeOffset);

        if (endTime > startTime) {
          segments.push({
            startTime,
            endTime,
            labels: [annotation.entity.description],
            confidence: segment.confidence,
          });
        }
      }
    }
  }

  // Process segment label annotations
  if (annotations.segmentLabelAnnotations && annotations.segmentLabelAnnotations.length > 0) {
    console.log('Found segment label annotations:', annotations.segmentLabelAnnotations.length);
    for (const annotation of annotations.segmentLabelAnnotations) {
      for (const segment of annotation.segments) {
        const startTime = timeOffsetToSeconds(segment.segment.startTimeOffset);
        const endTime = timeOffsetToSeconds(segment.segment.endTimeOffset);

        if (endTime > startTime) {
          segments.push({
            startTime,
            endTime,
            labels: [annotation.entity.description],
            confidence: segment.confidence,
          });
        }
      }
    }
  }

  // Process shot changes
  if (annotations.shotAnnotations && annotations.shotAnnotations.length > 0) {
    console.log('Found shot annotations:', annotations.shotAnnotations.length);
    for (const shot of annotations.shotAnnotations) {
      const startTime = timeOffsetToSeconds(shot.startTimeOffset);
      const endTime = timeOffsetToSeconds(shot.endTimeOffset);

      if (endTime > startTime) {
        segments.push({
          startTime,
          endTime,
          labels: ['Scene Change'],
          confidence: 1.0,
        });
      }
    }
  }

  // Merge overlapping segments with same labels
  const mergedSegments = [];
  const sortedSegments = segments.sort((a, b) => a.startTime - b.startTime);

  for (const segment of sortedSegments) {
    const lastSegment = mergedSegments[mergedSegments.length - 1];

    if (lastSegment && lastSegment.endTime >= segment.startTime && lastSegment.labels[0] === segment.labels[0]) {
      // Merge overlapping segments
      lastSegment.endTime = Math.max(lastSegment.endTime, segment.endTime);
      lastSegment.confidence = Math.max(lastSegment.confidence, segment.confidence);
    } else {
      mergedSegments.push(segment);
    }
  }

  console.log('Final processed segments:', mergedSegments);
  return mergedSegments;
}

exports.analyzeVideo = onObjectFinalized(
  {
    timeoutSeconds: 540,
    memory: '2GB',
    location: 'us-central1',
  },
  async (event) => {
    const object = event.data;
    console.log('Storage event received for video analysis:', {
      name: object.name,
      contentType: object.contentType,
    });

    // Only process original MP4 uploads in videos directory
    if (!object.name.startsWith('videos/') || !object.contentType.startsWith('video/')) {
      console.log('Not a video in videos directory, skipping analysis.');
      return null;
    }

    // Extract path information
    const filePath = object.name;
    const pathParts = filePath.split('/');
    const fileName = pathParts[2];
    const videoId = path.parse(fileName).name;

    // Function to find the video document
    async function findVideoDocument(retryCount = 0, maxRetries = 5) {
      if (retryCount >= maxRetries) {
        throw new Error('Max retries reached while waiting for video document');
      }

      console.log(`Attempt ${retryCount + 1} to find video document...`);

      // Try to get the document directly by ID first
      const db = getFirestore();
      const directDoc = await db.collection('videos').doc(videoId).get();

      if (directDoc.exists) {
        console.log('Found video document by ID');
        return directDoc;
      }

      // If not found by ID, try searching by storage URL
      const storageUrl = `https://storage.googleapis.com/${object.bucket}/${filePath}`;
      const querySnapshot = await db.collection('videos').where('videoUrl', '==', storageUrl).limit(1).get();

      if (!querySnapshot.empty) {
        console.log('Found video document by storage URL');
        return querySnapshot.docs[0];
      }

      // If document not found, wait and retry
      console.log('Video document not found, waiting before retry...');
      await new Promise((resolve) => setTimeout(resolve, 2000)); // Wait 2 seconds
      return findVideoDocument(retryCount + 1, maxRetries);
    }

    try {
      // Find the video document with retries
      const videoDoc = await findVideoDocument();
      const videoId = videoDoc.id;

      // Update status to in-progress
      console.log('Updating video analysis status to in-progress');
      const db = getFirestore();
      await db.collection('videos').doc(videoId).update({
        analysisStatus: 'inProgress',
      });

      // Initialize Video Intelligence API
      console.log('Initializing Video Intelligence API');
      const client = new VideoIntelligenceServiceClient();
      const gcsUri = `gs://${object.bucket}/${filePath}`;

      console.log('Starting video analysis:', { gcsUri });
      const [operation] = await client.annotateVideo({
        inputUri: gcsUri,
        features: ['SHOT_CHANGE_DETECTION', 'LABEL_DETECTION'],
        videoContext: {
          labelDetectionConfig: {
            labelDetectionMode: 'SHOT_MODE',
            stationaryCamera: false,
          },
        },
      });

      console.log('Waiting for analysis to complete...');
      const [result] = await operation.promise();
      console.log('Video analysis completed');

      const segments = processVideoResults(result);
      console.log('Processed segments:', segments);

      // Update Firestore with results
      console.log('Updating Firestore with analysis results');
      await db.collection('videos').doc(videoId).update({
        segments: segments,
        analysisStatus: 'completed',
      });

      console.log('Video analysis process completed successfully');
      return null;
    } catch (error) {
      console.error('Video analysis failed:', error);
      if (videoId) {
        // Update status to failed only if we found the video document
        const db = getFirestore();
        await db.collection('videos').doc(videoId).update({
          analysisStatus: 'failed',
          analysisError: error.message,
        });
      }
      throw error;
    }
  }
);
