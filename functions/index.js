const { initializeApp } = require('firebase-admin/app');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');
const { getStorage } = require('firebase-admin/storage');
const functions = require('firebase-functions');
const ffmpeg = require('fluent-ffmpeg');
const ffmpegInstaller = require('@ffmpeg-installer/ffmpeg');
const path = require('path');
const os = require('os');
const fs = require('fs');
const videoSegmentation = require('./videoSegmentation');
const { deleteVideoVectors } = require('./embeddings');

initializeApp();
ffmpeg.setFfmpegPath(ffmpegInstaller.path);

exports.generateHLS = functions.storage.onObjectFinalized(
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

// Add semantic search function
exports.searchVideoSegments = functions.https.onCall(
  {
    maxInstances: 10,
    timeoutSeconds: 30,
    memory: '256MB',
    secrets: ['OPENAI_API_KEY', 'PINECONE_API_KEY', 'PINECONE_ENVIRONMENT', 'PINECONE_INDEX_NAME'],
  },
  async (request) => {
    if (!request.auth) {
      throw new Error('Unauthorized: User must be authenticated');
    }

    const { query, limit = 10, filters = {} } = request.data;
    if (!query) {
      throw new Error('Missing required parameter: query');
    }

    try {
      console.log(`🔍 Searching for: "${query}" with filters:`, filters);

      // Generate embedding for search query
      const { generateEmbedding, searchVectors } = require('./embeddings');
      const queryEmbedding = await generateEmbedding(query);

      // Search Pinecone with filters
      const searchResults = await searchVectors(queryEmbedding, limit, filters);

      // Format results for client
      const formattedResults = searchResults.map((match) => ({
        score: match.score,
        segment: match.metadata,
        videoId: match.metadata.videoId,
      }));

      console.log(`✅ Found ${formattedResults.length} results`);
      return { segments: formattedResults };
    } catch (error) {
      console.error('❌ Search error:', error);
      throw new Error('Failed to perform search: ' + error.message);
    }
  }
);

exports.deleteVideo = functions.https.onCall(
  {
    maxInstances: 1,
    timeoutSeconds: 540,
    memory: '512MB',
    secrets: ['PINECONE_API_KEY', 'PINECONE_ENVIRONMENT', 'PINECONE_INDEX_NAME'],
  },
  async (request) => {
    // Verify authentication
    if (!request.auth) {
      throw new Error('Unauthorized: User must be authenticated');
    }

    const { videoId, userId } = request.data;
    if (!videoId || !userId) {
      throw new Error('Missing required parameters: videoId and userId are required');
    }

    // Verify user owns the video
    const firestore = getFirestore();
    const videoDoc = await firestore.collection('videos').doc(videoId).get();

    if (!videoDoc.exists) {
      throw new Error('Video not found');
    }

    const videoData = videoDoc.data();
    if (videoData.userId !== userId) {
      throw new Error('Unauthorized: User does not own this video');
    }

    if (request.auth.uid !== userId) {
      throw new Error('Unauthorized: User ID mismatch');
    }

    const storage = getStorage();
    const bucket = storage.bucket();
    const deletionResults = {
      storage: { success: true, errors: [] },
      firestore: { success: true, errors: [] },
    };

    try {
      console.log(`Starting deletion process for video ${videoId} owned by user ${userId}`);

      // Delete Pinecone vectors first
      try {
        console.log('Deleting Pinecone vectors...');
        await deleteVideoVectors(videoId);
        console.log('Successfully deleted Pinecone vectors');
      } catch (error) {
        console.error('Error deleting Pinecone vectors:', error);
        deletionResults.storage.errors.push({ type: 'pinecone', error });
      }

      // 1. Delete storage files
      try {
        // Delete video file
        const videoPath = `videos/${userId}/${videoId}.mp4`;
        try {
          await bucket.file(videoPath).delete();
          console.log('Original video file deleted');
        } catch (error) {
          if (error.code !== 404) {
            deletionResults.storage.errors.push({ type: 'video', error });
          }
          console.log('Original video file not found, continuing...');
        }

        // Delete thumbnail
        if (videoData.thumbnailUrl) {
          const thumbnailPath = `thumbnails/${userId}/${videoId}.jpg`;
          try {
            await bucket.file(thumbnailPath).delete();
            console.log('Thumbnail file deleted');
          } catch (error) {
            if (error.code !== 404) {
              deletionResults.storage.errors.push({ type: 'thumbnail', error });
            }
            console.log('Thumbnail file not found, continuing...');
          }
        }

        // Delete HLS files
        if (videoData.m3u8Url) {
          const hlsPrefix = `hls/${userId}/${videoId}/`;
          try {
            const [files] = await bucket.getFiles({ prefix: hlsPrefix });
            await Promise.all(files.map((file) => file.delete()));
            console.log(`Deleted ${files.length} HLS files`);
          } catch (error) {
            if (error.code !== 404) {
              deletionResults.storage.errors.push({ type: 'hls', error });
            }
            console.log('HLS directory not found, continuing...');
          }
        }
      } catch (error) {
        console.error('Error during storage cleanup:', error);
        deletionResults.storage.success = false;
        deletionResults.storage.errors.push({ type: 'general', error });
      }

      // 2. Delete Firestore documents
      try {
        console.log('Debugging bookmark query for videoId:', videoId);

        // First try a direct query to see what's in the bookmarkedVideos collection
        const directBookmarkQuery = await firestore.collectionGroup('bookmarkedVideos').get();

        console.log(
          'All bookmarkedVideos documents:',
          directBookmarkQuery.docs.map((doc) => ({
            path: doc.ref.path,
            data: doc.data(),
            id: doc.id,
          }))
        );

        // Now get bookmarks by matching the document ID
        const bookmarksSnapshot = {
          docs: directBookmarkQuery.docs.filter((doc) => doc.id === videoId),
        };

        console.log('Filtered bookmarks result:', {
          found: bookmarksSnapshot.docs.length,
          paths: bookmarksSnapshot.docs.map((doc) => doc.ref.path),
          data: bookmarksSnapshot.docs.map((doc) => doc.data()),
        });

        // Get the other data as well
        const [commentsSnapshot, likesSnapshot] = await Promise.all([
          firestore
            .collectionGroup('comments')
            .where('videoId', '==', videoId)
            .get()
            .catch((error) => {
              console.error('Error fetching comments:', error);
              deletionResults.firestore.errors.push({ type: 'comments_query', error });
              return { docs: [] };
            }),
          firestore
            .collectionGroup('likedVideos')
            .where('videoId', '==', videoId)
            .get()
            .catch((error) => {
              console.error('Error fetching likes:', error);
              deletionResults.firestore.errors.push({ type: 'likes_query', error });
              return { docs: [] };
            }),
        ]);

        console.log(
          `Found ${commentsSnapshot.docs.length} comments, ${likesSnapshot.docs.length} likes, and ${bookmarksSnapshot.docs.length} bookmarks to delete`
        );

        // Process deletions in batches
        const BATCH_SIZE = 500;
        const batches = [];
        let currentBatch = firestore.batch();
        let operationCount = 0;

        const addToBatch = (ref) => {
          currentBatch.delete(ref);
          operationCount++;

          if (operationCount === BATCH_SIZE) {
            batches.push(currentBatch.commit());
            currentBatch = firestore.batch();
            operationCount = 0;
          }
        };

        // Add all deletions to batches
        [...commentsSnapshot.docs, ...likesSnapshot.docs, ...bookmarksSnapshot.docs].forEach((doc) => {
          addToBatch(doc.ref);
        });

        // Delete the video document and update user counts
        currentBatch.delete(videoDoc.ref);
        operationCount++;

        const userRef = firestore.collection('users').doc(userId);
        currentBatch.update(userRef, {
          postsCount: FieldValue.increment(-1),
          likesCount: FieldValue.increment(-videoData.likes || 0),
        });
        operationCount++;

        // Add final batch if needed
        if (operationCount > 0) {
          batches.push(currentBatch.commit());
        }

        // Execute all batches
        if (batches.length > 0) {
          console.log(`Executing ${batches.length} batch(es) of deletions...`);
          await Promise.all(batches);
          console.log(`Successfully executed ${batches.length} batch(es) of deletions`);
        }

        return {
          success: true,
          deletedCounts: {
            comments: commentsSnapshot.docs.length,
            likes: likesSnapshot.docs.length,
            bookmarks: bookmarksSnapshot.docs.length,
          },
          deletionResults,
        };
      } catch (error) {
        console.error('Error during Firestore cleanup:', error);
        deletionResults.firestore.success = false;
        deletionResults.firestore.errors.push({ type: 'batch_operations', error });
        throw error;
      }
    } catch (error) {
      console.error('Error during video deletion:', {
        error: {
          code: error.code,
          message: error.message,
          details: error.details,
          stack: error.stack,
        },
        videoId,
        userId,
        deletionResults,
      });
      throw new Error(`Failed to delete video: ${error.message} (Code: ${error.code})`);
    }
  }
);
