const { Pinecone } = require('@pinecone-database/pinecone');
const OpenAI = require('openai');

// Get environment variables with defaults for development
const PINECONE_INDEX_NAME = process.env.PINECONE_INDEX_NAME || 'quiktok';
const PINECONE_API_KEY = process.env.PINECONE_API_KEY;

// Add debug logging
console.log('Environment Variables:', {
  PINECONE_INDEX_NAME: process.env.PINECONE_INDEX_NAME,
  has_PINECONE_API_KEY: !!process.env.PINECONE_API_KEY,
  process_env_keys: Object.keys(process.env),
});

/**
 * Generates an embedding for the given text using OpenAI's text-embedding-3-large model
 * @param {string} text - The text to generate an embedding for
 * @returns {Promise<number[]>} The embedding vector
 */
async function generateEmbedding(text) {
  try {
    const openai = new OpenAI({ apiKey: process.env.OPENAI_API_KEY });
    const response = await openai.embeddings.create({
      model: 'text-embedding-3-large',
      input: text,
      encoding_format: 'float',
    });
    return response.data[0].embedding;
  } catch (error) {
    console.error('Error generating embedding:', error);
    throw error;
  }
}

/**
 * Uploads a vector to Pinecone with enhanced metadata
 * @param {Object} vector - The vector object to upload
 * @param {string} vector.id - Unique identifier for the vector
 * @param {number[]} vector.values - The embedding values
 * @param {Object} vector.metadata - Metadata associated with the vector
 * @param {Object} additionalMetadata - Additional video context metadata
 */
async function uploadToVectorDB(vector, additionalMetadata = {}) {
  try {
    console.log('Initializing Pinecone client with:', {
      indexName: PINECONE_INDEX_NAME,
      hasApiKey: !!PINECONE_API_KEY,
    });

    const pinecone = new Pinecone({
      apiKey: PINECONE_API_KEY,
    });

    console.log('Getting Pinecone index:', PINECONE_INDEX_NAME);
    const index = pinecone.index(PINECONE_INDEX_NAME);

    // Enhance metadata with additional context and timestamps
    const enhancedMetadata = {
      ...vector.metadata,
      ...additionalMetadata,
      createdAt: new Date().toISOString(),
      duration: vector.metadata.endTime - vector.metadata.startTime,
    };

    console.log(`Upserting vector with ID: ${vector.id}`);
    console.log('Vector metadata:', JSON.stringify(enhancedMetadata, null, 2));

    await index.upsert([
      {
        id: vector.id,
        values: vector.values,
        metadata: enhancedMetadata,
      },
    ]);

    console.log('Vector upsert successful');
  } catch (error) {
    console.error('Error uploading to Pinecone:', error);
    console.error('Error details:', {
      name: error.name,
      message: error.message,
      cause: error.cause,
      stack: error.stack,
    });
    throw error;
  }
}

/**
 * Deletes all vectors associated with a video
 * @param {string} videoId - The ID of the video whose vectors should be deleted
 * @returns {Promise<void>}
 */
async function deleteVideoVectors(videoId) {
  try {
    console.log(`🗑️ Deleting vectors for video: ${videoId}`);
    const pinecone = new Pinecone({
      apiKey: PINECONE_API_KEY,
    });
    const index = pinecone.index(PINECONE_INDEX_NAME);

    // First, fetch all vector IDs for this video
    const queryResponse = await index.query({
      vector: Array(3072).fill(0), // Match text-embedding-3-large dimension
      filter: { videoId: { $eq: videoId } },
      includeMetadata: true,
      topK: 10000, // Get all matches
    });

    if (queryResponse.matches && queryResponse.matches.length > 0) {
      const vectorIds = queryResponse.matches.map((match) => match.id);
      console.log(`Found ${vectorIds.length} vectors to delete for video ${videoId}`);

      // Delete vectors in batches of 1000
      const batchSize = 1000;
      for (let i = 0; i < vectorIds.length; i += batchSize) {
        const batch = vectorIds.slice(i, i + batchSize);
        await index.deleteMany(batch);
        console.log(`Deleted batch of ${batch.length} vectors`);
      }
    } else {
      console.log(`No vectors found for video ${videoId}`);
    }

    console.log(`✅ Successfully deleted vectors for video: ${videoId}`);
  } catch (error) {
    console.error(`❌ Error deleting vectors for video ${videoId}:`, error);
    throw error;
  }
}

/**
 * Searches for similar vectors in Pinecone with filtering options
 * @param {number[]} queryVector - The query vector to search with
 * @param {number} limit - Maximum number of results to return
 * @param {Object} filters - Optional filters to apply to the search
 * @returns {Promise<Array>} Array of matching results with scores and metadata
 */
async function searchVectors(queryVector, limit = 10, filters = {}) {
  try {
    const pinecone = new Pinecone({
      apiKey: PINECONE_API_KEY,
    });
    const index = pinecone.index(PINECONE_INDEX_NAME);

    // Build filter based on provided criteria
    const filter = {};
    if (filters.minDuration) filter.duration = { $gte: filters.minDuration };
    if (filters.maxDuration) filter.duration = { ...filter.duration, $lte: filters.maxDuration };
    if (filters.username) filter.username = { $eq: filters.username };
    if (filters.excludeFiller) filter.isFiller = { $eq: false };
    if (filters.after) filter.createdAt = { $gte: filters.after };

    const results = await index.query({
      vector: queryVector,
      topK: limit,
      includeMetadata: true,
      filter: Object.keys(filter).length > 0 ? filter : undefined,
    });

    return results.matches;
  } catch (error) {
    console.error('Error searching vectors:', error);
    throw error;
  }
}

module.exports = {
  generateEmbedding,
  uploadToVectorDB,
  searchVectors,
  deleteVideoVectors,
};
