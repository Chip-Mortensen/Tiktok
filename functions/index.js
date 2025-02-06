const { initializeApp } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const { getStorage } = require('firebase-admin/storage');
const { onObjectFinalized } = require('firebase-functions/v2/storage');
const ffmpeg = require('fluent-ffmpeg');
const ffmpegInstaller = require('@ffmpeg-installer/ffmpeg');
const path = require('path');
const os = require('os');
const fs = require('fs');
const videoSegmentation = require('./videoSegmentation');

initializeApp();
ffmpeg.setFfmpegPath(ffmpegInstaller.path);

exports.generateHLS = onObjectFinalized(
  {
    timeoutSeconds: 540,
    memory: '2GB',
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

// Export video segmentation function
exports.transcribeAndSegmentAudio = videoSegmentation.transcribeAndSegmentAudio;
