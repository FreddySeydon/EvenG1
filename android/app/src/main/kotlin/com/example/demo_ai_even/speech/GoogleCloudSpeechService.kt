package com.example.demo_ai_even.speech

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.google.auth.oauth2.GoogleCredentials
import com.google.api.client.http.GenericUrl
import com.google.api.client.http.HttpRequestFactory
import com.google.api.client.http.HttpRequest
import com.google.api.client.http.javanet.NetHttpTransport
import com.google.api.client.http.json.JsonHttpContent
import com.google.api.client.json.jackson2.JacksonFactory
import com.google.api.client.json.JsonObjectParser
import kotlinx.coroutines.*
import java.io.ByteArrayInputStream
import java.io.InputStream
import java.util.concurrent.atomic.AtomicBoolean
import java.util.Base64

/**
 * Google Cloud Speech-to-Text Service
 * Handles speech recognition from PCM audio data from glasses using REST API
 */
class GoogleCloudSpeechService private constructor() {
    
    companion object {
        private const val TAG = "GoogleCloudSpeechService"
        private const val SPEECH_API_URL = "https://speech.googleapis.com/v1/speech:recognize"
        private const val STREAMING_API_URL = "https://speech.googleapis.com/v1/speech:streamingrecognize"
        @JvmStatic
        val instance: GoogleCloudSpeechService by lazy { GoogleCloudSpeechService() }
    }
    
    private var httpRequestFactory: HttpRequestFactory? = null
    private var credentials: GoogleCredentials? = null
    private var isStreaming = AtomicBoolean(false)
    private var isStopped = AtomicBoolean(false) // Track if recognition has been stopped and final result obtained
    private val recognitionResults = StringBuilder()
    private val audioBuffer = mutableListOf<ByteArray>()
    private var recognitionJob: Job? = null
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    // Audio buffering - we accumulate all audio and send it for final recognition when recording stops
    
    // Service account JSON content - Set this via initialize() method
    private var serviceAccountJson: String? = null
    private var context: Context? = null
    
    // Language code (e.g., "en-US", "zh-CN") - default to en-US
    private var languageCode: String = "en-US"
    
    /**
     * Initialize the service with service account JSON
     * @param context Android context
     * @param serviceAccountJson Service account JSON as string (or null to use file in assets)
     */
    fun initialize(context: Context, serviceAccountJson: String? = null) {
        this.context = context.applicationContext
        this.serviceAccountJson = serviceAccountJson
        Log.d(TAG, "Google Cloud Speech Service initialized")
    }
    
    /**
     * Start streaming recognition
     * Note: REST API doesn't support true streaming, so we buffer audio and send periodically
     * @param languageCode Language code (e.g., "en-US")
     */
    suspend fun startRecognition(languageCode: String = "en-US") {
        if (isStreaming.get()) {
            Log.w(TAG, "Recognition already started")
            return
        }
        
        val ctx = context ?: run {
            Log.e(TAG, "Context not initialized")
            return
        }
        
        try {
            this.languageCode = languageCode
            recognitionResults.clear()
            audioBuffer.clear()
            isStopped.set(false) // Reset stopped flag when starting new recognition
            
            // Load credentials from service account JSON
            credentials = if (serviceAccountJson != null) {
                // Use provided JSON string
                GoogleCredentials.fromStream(ByteArrayInputStream(serviceAccountJson!!.toByteArray()))
                    .createScoped(listOf("https://www.googleapis.com/auth/cloud-platform"))
            } else {
                // Try to load from assets/google-cloud-credentials.json
                val inputStream: InputStream = try {
                    ctx.assets.open("google-cloud-credentials.json")
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to load credentials from assets. Error: ${e.message}")
                    throw IllegalStateException("Service account credentials not found. Please set up credentials.")
                }
                GoogleCredentials.fromStream(inputStream)
                    .createScoped(listOf("https://www.googleapis.com/auth/cloud-platform"))
            }
            
            // Refresh credentials to get access token
            credentials!!.refreshIfExpired()
            val accessToken = credentials!!.accessToken.tokenValue
            
            if (accessToken.isNullOrEmpty()) {
                throw IllegalStateException("Failed to get access token from credentials")
            }
            
            Log.d(TAG, "Got access token (length: ${accessToken.length})")
            
            // Create HTTP request factory with credentials
            val transport = NetHttpTransport()
            val jsonFactory = JacksonFactory.getDefaultInstance()
            httpRequestFactory = transport.createRequestFactory { request ->
                request.headers.setAuthorization("Bearer $accessToken")
            }
            
            isStreaming.set(true)
            
            Log.d(TAG, "Started Google Cloud Speech recognition for language: $languageCode")
            
        } catch (e: Exception) {
            Log.e(TAG, "Error starting recognition: ${e.message}", e)
            isStreaming.set(false)
            httpRequestFactory = null
            credentials = null
            throw e
        }
    }
    
    /**
     * Append PCM audio data to the recognition buffer
     * Audio will be sent periodically for recognition
     * @param pcmData PCM audio data (16-bit, 16kHz, mono)
     */
    fun appendPCMData(pcmData: ByteArray) {
        // Don't accept new audio if recognition has been stopped and final result obtained
        // Silently ignore - SpeechRecognitionManager should check this before calling
        if (isStopped.get()) {
            return
        }
        
        // Buffer audio even if not streaming yet - it will be processed when streaming starts
        // This prevents losing audio that arrives before streaming is ready
        synchronized(audioBuffer) {
            audioBuffer.add(pcmData)
            val totalSize = audioBuffer.sumOf { it.size }
            if (isStreaming.get()) {
                Log.d(TAG, "Buffered audio: ${audioBuffer.size} chunks, total ${totalSize} bytes (streaming)")
            } else {
                Log.d(TAG, "Buffered audio: ${audioBuffer.size} chunks, total ${totalSize} bytes (not streaming yet - will process when ready)")
            }
        }
        
        // Don't process audio automatically during recording
        // We'll only process when stopRecognition() is called to get the full context
        // This prevents sending partial/interim results
        // Audio is buffered and will be sent for final recognition when recording stops
    }
    
    /**
     * Process audio immediately (for final audio when stopping)
     * This sends all accumulated audio for final recognition
     */
    private suspend fun processAudioImmediate(audioData: ByteArray) {
        if (httpRequestFactory == null) {
            Log.e(TAG, "HTTP request factory is null, cannot process final audio")
            return
        }
        
        // Clear previous results since we're doing final recognition
        recognitionResults.clear()
        
        // Encode audio to base64
        val audioBase64 = Base64.getEncoder().encodeToString(audioData)
        
        // Create recognition request with final result settings
        val requestBody = mapOf(
            "config" to mapOf(
                "encoding" to "LINEAR16",
                "sampleRateHertz" to 16000,
                "languageCode" to languageCode,
                "enableAutomaticPunctuation" to true,
                "model" to "latest_long",
                "enableWordTimeOffsets" to false,
                "useEnhanced" to true
            ),
            "audio" to mapOf(
                "content" to audioBase64
            )
        )
        
        sendRecognitionRequest(requestBody, audioData.size, isFinal = true)
    }
    
    /**
     * Process buffered audio and send to Google Cloud for recognition
     */
    private suspend fun processBufferedAudio() {
        if (!isStreaming.get() || httpRequestFactory == null) {
            return
        }
        
        val audioChunks: List<ByteArray>
        synchronized(audioBuffer) {
            if (audioBuffer.isEmpty()) {
                return
            }
            audioChunks = audioBuffer.toList()
            audioBuffer.clear()
        }
        
        // Combine audio chunks
        val totalSize = audioChunks.sumOf { it.size }
        val combinedAudio = ByteArray(totalSize)
        var offset = 0
        for (chunk in audioChunks) {
            System.arraycopy(chunk, 0, combinedAudio, offset, chunk.size)
            offset += chunk.size
        }
        
        // Encode audio to base64
        val audioBase64 = Base64.getEncoder().encodeToString(combinedAudio)
        
        // Create recognition request
        val requestBody = mapOf(
            "config" to mapOf(
                "encoding" to "LINEAR16",
                "sampleRateHertz" to 16000,
                "languageCode" to languageCode,
                "enableAutomaticPunctuation" to true,
                "model" to "latest_long"
            ),
            "audio" to mapOf(
                "content" to audioBase64
            )
        )
        
        // Don't send interim results - only send when stopRecognition() is called
        // This is a periodic check, so we won't send results here
        // sendRecognitionRequest(requestBody, combinedAudio.size, isFinal = false)
    }
    
    /**
     * Send recognition request to Google Cloud Speech-to-Text API
     * @param isFinal If true, this is the final request and results should be sent to Flutter
     */
    private suspend fun sendRecognitionRequest(requestBody: Map<String, Any>, audioSize: Int, isFinal: Boolean = false) {
        if (httpRequestFactory == null) {
            Log.e(TAG, "HTTP request factory is null, cannot send recognition request")
            return
        }
        
        try {
            Log.d(TAG, "Sending $audioSize bytes of audio for recognition")
            
            val url = GenericUrl(SPEECH_API_URL)
            val jsonFactory = JacksonFactory.getDefaultInstance()
            val content = JsonHttpContent(jsonFactory, requestBody)
            val request = httpRequestFactory!!.buildPostRequest(url, content)
            request.headers.setContentType("application/json")
            
            val response = request.execute()
            val statusCode = response.statusCode
            
            // Read response content before closing
            val responseBody = try {
                response.parseAsString()
            } catch (e: Exception) {
                Log.e(TAG, "Error reading response body: ${e.message}", e)
                // Ensure response is closed even if reading fails
                try {
                    response.content?.close()
                } catch (closeError: Exception) {
                    // Ignore close errors
                }
                return
            }
            
            Log.d(TAG, "Recognition response status: $statusCode")
            Log.d(TAG, "Recognition response body: $responseBody")
            
            // Ensure response stream is closed
            try {
                response.content?.close()
            } catch (e: Exception) {
                // Ignore close errors - stream might already be closed
            }
            
            if (statusCode != 200) {
                Log.e(TAG, "Recognition request failed with status: $statusCode, body: $responseBody")
                return
            }
            
            // Parse JSON response properly
            try {
                val parser = JsonObjectParser(jsonFactory)
                @Suppress("UNCHECKED_CAST")
                val jsonResponse = parser.parseAndClose(
                    java.io.ByteArrayInputStream(responseBody.toByteArray(java.nio.charset.Charset.forName("UTF-8"))), 
                    java.nio.charset.Charset.forName("UTF-8"), 
                    Map::class.java
                ) as Map<String, Any>
                
                // Check for errors
                if (jsonResponse.containsKey("error")) {
                    val error = jsonResponse["error"] as Map<String, Any>
                    Log.e(TAG, "Recognition error: ${error["message"]}")
                    return
                }
                
                // Extract results
                val results = jsonResponse["results"] as? List<Map<String, Any>>
                if (results != null && results.isNotEmpty()) {
                    for (result in results) {
                        val alternatives = result["alternatives"] as? List<Map<String, Any>>
                        if (alternatives != null && alternatives.isNotEmpty()) {
                            val alternative = alternatives[0]
                            val transcript = alternative["transcript"] as? String
                            val confidence = alternative["confidence"] as? Double
                            
                            if (transcript != null && transcript.isNotEmpty()) {
                                Log.d(TAG, "Recognized text: '$transcript' (confidence: $confidence, isFinal: $isFinal)")
                                recognitionResults.append(transcript).append(" ")
                                
                                // Only send to Flutter if this is a final request (from stopRecognition)
                                // This ensures we wait for the full context before sending
                                if (isFinal) {
                                    Log.d(TAG, "Final recognition result accumulated: '${recognitionResults.toString().trim()}'")
                                    // Results will be sent in stopRecognition() after processing
                                }
                            } else {
                                Log.w(TAG, "Empty transcript in response")
                            }
                        }
                    }
                } else {
                    Log.d(TAG, "No results in recognition response (might be silence or no speech)")
                }
                
            } catch (e: Exception) {
                Log.e(TAG, "Error parsing JSON response: ${e.message}", e)
                Log.d(TAG, "Raw response: $responseBody")
                e.printStackTrace()
            }
            
        } catch (e: Exception) {
            Log.e(TAG, "Error sending audio for recognition: ${e.message}", e)
            e.printStackTrace()
        }
    }
    
    /**
     * Stop recognition and get final results
     */
    suspend fun stopRecognition(): String {
        // Check if we have buffered audio even if not streaming
        val hasBufferedAudio: Boolean
        synchronized(audioBuffer) {
            hasBufferedAudio = audioBuffer.isNotEmpty()
        }
        
        // If not streaming and no buffered audio, return what we have
        if (!isStreaming.get() && !hasBufferedAudio) {
            val existingText = recognitionResults.toString().trim()
            Log.d(TAG, "Stopped recognition (was not streaming, no buffered audio) - Final text: '$existingText'")
            return existingText
        }
        
        try {
            // Ensure we're initialized before processing
            // If streaming never started but we have audio, try to initialize now
            if (httpRequestFactory == null && hasBufferedAudio) {
                Log.w(TAG, "HTTP request factory is null but we have buffered audio - attempting to initialize")
                try {
                    val ctx = context ?: run {
                        Log.e(TAG, "Context is null, cannot initialize")
                        return recognitionResults.toString().trim()
                    }
                    
                    // Set default language code if not set
                    if (languageCode.isEmpty()) {
                        languageCode = "en-US"
                        Log.d(TAG, "Set default language code to en-US")
                    }
                    
                    // Try to initialize if we have credentials
                    val localCredentials = if (serviceAccountJson != null) {
                        GoogleCredentials.fromStream(ByteArrayInputStream(serviceAccountJson!!.toByteArray()))
                            .createScoped(listOf("https://www.googleapis.com/auth/cloud-platform"))
                    } else {
                        try {
                            val inputStream = ctx.assets.open("google-cloud-credentials.json")
                            GoogleCredentials.fromStream(inputStream)
                                .createScoped(listOf("https://www.googleapis.com/auth/cloud-platform"))
                        } catch (e: Exception) {
                            Log.e(TAG, "Failed to load credentials: ${e.message}")
                            return recognitionResults.toString().trim()
                        }
                    }
                    
                    localCredentials.refreshIfExpired()
                    val accessToken = localCredentials.accessToken.tokenValue
                    
                    // Store credentials for reuse
                    this.credentials = localCredentials
                    
                    val transport = NetHttpTransport()
                    val jsonFactory = JacksonFactory.getDefaultInstance()
                    httpRequestFactory = transport.createRequestFactory { request ->
                        request.headers.setAuthorization("Bearer $accessToken")
                    }
                    Log.d(TAG, "Initialized HTTP factory for final recognition (language: $languageCode)")
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to initialize for final recognition: ${e.message}", e)
                    return recognitionResults.toString().trim()
                }
            }
            
            isStreaming.set(false)
            
            // Process ALL buffered audio as a single request for final recognition
            // This ensures we get the full context instead of partial results
            val finalAudioChunks: List<ByteArray>
            synchronized(audioBuffer) {
                finalAudioChunks = audioBuffer.toList()
                audioBuffer.clear()
            }
            
            if (finalAudioChunks.isNotEmpty()) {
                // Combine all audio chunks
                val totalSize = finalAudioChunks.sumOf { it.size }
                if (totalSize > 0) {
                    val combinedAudio = ByteArray(totalSize)
                    var offset = 0
                    for (chunk in finalAudioChunks) {
                        System.arraycopy(chunk, 0, combinedAudio, offset, chunk.size)
                        offset += chunk.size
                    }
                    
                    Log.d(TAG, "Processing final audio: ${combinedAudio.size} bytes for complete recognition")
                    
                    // Process this audio for final recognition
                    if (httpRequestFactory != null) {
                        processAudioImmediate(combinedAudio)
                        
                        // Wait 2 seconds for the API response to ensure transcription is complete
                        delay(2000) // 2 second buffer time for API response
                    } else {
                        Log.e(TAG, "Cannot process audio - httpRequestFactory is null")
                    }
                }
            } else {
                Log.d(TAG, "No buffered audio to process")
            }
            
            // Get the final accumulated text
            val finalText = recognitionResults.toString().trim()
            Log.d(TAG, "Stopped recognition - Final text: '$finalText'")
            
            // Mark as stopped - this will prevent any new audio from being buffered
            isStopped.set(true)
            
            // Clear the audio buffer since we've already processed it and have the final result
            synchronized(audioBuffer) {
                audioBuffer.clear()
            }
            
            // Send final results to Flutter (must be on main thread)
            // Use CompletableDeferred to ensure the event is sent before returning
            val deferred = kotlinx.coroutines.CompletableDeferred<Unit>()
            val mainHandler = Handler(Looper.getMainLooper())
            
            if (finalText.isNotEmpty()) {
                Log.d(TAG, "Preparing to send transcription to Flutter: '$finalText'")
                mainHandler.post {
                    try {
                        val eventData = mapOf("script" to finalText)
                        com.example.demo_ai_even.bluetooth.BleChannelHelper.bleSpeechRecognize(eventData)
                        Log.d(TAG, "Sent final recognition result to Flutter: '$finalText'")
                    } catch (e: Exception) {
                        Log.e(TAG, "Error sending transcription to Flutter: ${e.message}", e)
                    } finally {
                        deferred.complete(Unit)
                    }
                }
            } else {
                Log.w(TAG, "No text recognized, sending empty result")
                mainHandler.post {
                    try {
                        com.example.demo_ai_even.bluetooth.BleChannelHelper.bleSpeechRecognize(
                            mapOf("script" to "")
                        )
                        Log.d(TAG, "Sent empty transcription result to Flutter")
                    } catch (e: Exception) {
                        Log.e(TAG, "Error sending empty transcription to Flutter: ${e.message}", e)
                    } finally {
                        deferred.complete(Unit)
                    }
                }
            }
            
            // Wait for the event to be posted (with timeout to avoid hanging)
            try {
                kotlinx.coroutines.withTimeout(2000) {
                    deferred.await()
                }
                Log.d(TAG, "Event posting completed")
            } catch (e: kotlinx.coroutines.TimeoutCancellationException) {
                Log.e(TAG, "Timeout waiting for event to be posted to Flutter")
            }
            
            // Cleanup (but keep httpRequestFactory if we might need it again)
            // Don't clear credentials yet - might be reused
            // httpRequestFactory = null
            // credentials = null
            
            return finalText
            
        } catch (e: Exception) {
            Log.e(TAG, "Error stopping recognition: ${e.message}", e)
            e.printStackTrace()
            
            // Still try to send whatever we have
            val finalText = recognitionResults.toString().trim()
            if (finalText.isNotEmpty()) {
                try {
                    val mainHandler = Handler(Looper.getMainLooper())
                    mainHandler.post {
                        com.example.demo_ai_even.bluetooth.BleChannelHelper.bleSpeechRecognize(
                            mapOf("script" to finalText)
                        )
                    }
                    delay(100) // Small delay to ensure message is queued
                } catch (e2: Exception) {
                    Log.e(TAG, "Error sending final result after exception: ${e2.message}", e2)
                }
            }
            
            return finalText
        }
    }
    
    /**
     * Check if service is initialized
     */
    fun isInitialized(): Boolean {
        return context != null && (serviceAccountJson != null || 
            try {
                context?.assets?.open("google-cloud-credentials.json")
                true
            } catch (e: Exception) {
                false
            })
    }
    
    /**
     * Check if recognition is currently streaming/active
     */
    fun isStreaming(): Boolean {
        return isStreaming.get()
    }
    
    /**
     * Check if recognition has been stopped and final result obtained
     */
    fun isStopped(): Boolean {
        return isStopped.get()
    }
    
    /**
     * Cleanup resources
     */
    fun dispose() {
        scope.cancel()
        httpRequestFactory = null
        credentials = null
        recognitionResults.clear()
        audioBuffer.clear()
    }
}
