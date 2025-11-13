package com.example.demo_ai_even.speech

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.speech.SpeechRecognizer
import android.util.Log
import androidx.core.content.ContextCompat
import com.example.demo_ai_even.bluetooth.BleChannelHelper
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import java.util.concurrent.atomic.AtomicBoolean

class SpeechRecognitionManager private constructor() {
    
    companion object {
        private const val TAG = "SpeechRecognitionManager"
        @JvmStatic
        val instance: SpeechRecognitionManager by lazy { SpeechRecognitionManager() }
    }
    
    private var speechRecognizer: SpeechRecognizer? = null
    private var context: Context? = null
    private var isStarted = AtomicBoolean(false)
    private var isStopping = AtomicBoolean(false)
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    
    private val languageMap = mapOf(
        "CN" to "zh-CN",
        "EN" to "en-US",
        "RU" to "ru-RU",
        "KR" to "ko-KR",
        "JP" to "ja-JP",
        "ES" to "es-ES",
        "FR" to "fr-FR",
        "DE" to "de-DE",
        "NL" to "nl-NL",
        "NB" to "nb-NO",
        "DA" to "da-DK",
        "SV" to "sv-SE",
        "FI" to "fi-FI",
        "IT" to "it-IT"
    )
    
    private val recognitionResults = StringBuilder()
    
    private val recognitionListener = object : android.speech.RecognitionListener {
        override fun onReadyForSpeech(params: android.os.Bundle?) {
            Log.d(TAG, "onReadyForSpeech")
        }
        
        override fun onBeginningOfSpeech() {
            Log.d(TAG, "onBeginningOfSpeech")
        }
        
        override fun onRmsChanged(rmsdB: Float) {
            // Ignore
        }
        
        override fun onBufferReceived(buffer: ByteArray?) {
            // Ignore
        }
        
        override fun onEndOfSpeech() {
            Log.d(TAG, "onEndOfSpeech")
        }
        
        override fun onError(error: Int) {
            when (error) {
                SpeechRecognizer.ERROR_AUDIO -> Log.e(TAG, "ERROR_AUDIO")
                SpeechRecognizer.ERROR_CLIENT -> Log.e(TAG, "ERROR_CLIENT")
                SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> Log.e(TAG, "ERROR_INSUFFICIENT_PERMISSIONS")
                SpeechRecognizer.ERROR_NETWORK -> Log.e(TAG, "ERROR_NETWORK")
                SpeechRecognizer.ERROR_NETWORK_TIMEOUT -> Log.e(TAG, "ERROR_NETWORK_TIMEOUT")
                SpeechRecognizer.ERROR_NO_MATCH -> Log.w(TAG, "ERROR_NO_MATCH - No speech recognized")
                SpeechRecognizer.ERROR_RECOGNIZER_BUSY -> Log.e(TAG, "ERROR_RECOGNIZER_BUSY")
                SpeechRecognizer.ERROR_SERVER -> Log.e(TAG, "ERROR_SERVER")
                SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> Log.w(TAG, "ERROR_SPEECH_TIMEOUT - No speech input")
            }
        }
        
        override fun onResults(results: android.os.Bundle?) {
            Log.d(TAG, "onResults")
            val matches = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
            if (!matches.isNullOrEmpty()) {
                val text = matches[0]
                recognitionResults.append(text).append(" ")
                Log.d(TAG, "Recognized text: $text")
            }
        }
        
        override fun onPartialResults(partialResults: android.os.Bundle?) {
            val matches = partialResults?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
            if (!matches.isNullOrEmpty()) {
                Log.d(TAG, "Partial recognized text: ${matches[0]}")
            }
        }
        
        override fun onEvent(eventType: Int, params: android.os.Bundle?) {
            // Ignore
        }
    }
    
    fun initialize(context: Context) {
        this.context = context.applicationContext
        this.context?.let { ctx ->
            // Initialize Google Cloud Speech Service (will use if credentials are available)
            // This checks for credentials file in assets/google-cloud-credentials.json
            GoogleCloudSpeechService.instance.initialize(ctx)
            
            if (GoogleCloudSpeechService.instance.isInitialized()) {
                Log.d(TAG, "Google Cloud Speech-to-Text initialized (will use glasses microphone)")
            } else {
                Log.w(TAG, "Google Cloud Speech-to-Text not initialized - using Android SpeechRecognizer (phone mic only)")
            }
            
            // Also initialize Android SpeechRecognizer as fallback
            if (SpeechRecognizer.isRecognitionAvailable(ctx)) {
                speechRecognizer = SpeechRecognizer.createSpeechRecognizer(ctx)
                speechRecognizer?.setRecognitionListener(recognitionListener)
                Log.d(TAG, "Android SpeechRecognizer initialized (fallback)")
            } else {
                Log.e(TAG, "Speech recognition not available on this device")
            }
        }
    }
    
    private var usingGoogleCloud = false
    
    fun startRecognition(identifier: String) {
        // Don't start if already started or if we're in the process of stopping
        if (isStopping.get()) {
            Log.w(TAG, "Recognition is currently stopping, cannot start new session")
            return
        }
        if (!isStarted.compareAndSet(false, true)) {
            Log.w(TAG, "Recognition already started")
            return
        }
        
        val ctx = context ?: run {
            Log.e(TAG, "Context not initialized")
            isStarted.set(false)
            return
        }
        
        recognitionResults.clear()
        
        Log.d(TAG, "Starting speech recognition for language: $identifier")
        
        // Try Google Cloud Speech-to-Text first (if initialized)
        if (GoogleCloudSpeechService.instance.isInitialized()) {
            Log.d(TAG, "Using Google Cloud Speech-to-Text (supports PCM from glasses)")
            usingGoogleCloud = true
            val languageCode = languageMap[identifier] ?: "en-US"
            // Start Google Cloud and wait for it to be ready before returning
            // This ensures streaming is active before PCM data starts arriving
            scope.launch(Dispatchers.IO) {
                try {
                    GoogleCloudSpeechService.instance.startRecognition(languageCode)
                    // Verify streaming started successfully - wait a bit if needed
                    var retries = 0
                    while (!GoogleCloudSpeechService.instance.isStreaming() && retries < 10) {
                        kotlinx.coroutines.delay(100)
                        retries++
                    }
                    if (!GoogleCloudSpeechService.instance.isStreaming()) {
                        throw IllegalStateException("Google Cloud Speech started but is not streaming after ${retries * 100}ms")
                    }
                    Log.d(TAG, "Google Cloud Speech-to-Text is now streaming and ready for PCM data (waited ${retries * 100}ms)")
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to start Google Cloud Speech: ${e.message}", e)
                    usingGoogleCloud = false
                    isStarted.set(false)
                    // Fallback to Android SpeechRecognizer
                    if (speechRecognizer != null && 
                        ContextCompat.checkSelfPermission(ctx, Manifest.permission.RECORD_AUDIO) 
                        == PackageManager.PERMISSION_GRANTED) {
                        isStarted.set(true)
                        startListening()
                    }
                }
            }
        } else {
            // Fallback: Android SpeechRecognizer only works with AudioRecord input (microphone)
            // It cannot process raw PCM data from Bluetooth streams directly
            Log.w(TAG, "Google Cloud Speech not initialized, using Android SpeechRecognizer (phone mic only)")
            usingGoogleCloud = false
            
            if (speechRecognizer == null) {
                Log.e(TAG, "SpeechRecognizer not initialized")
                isStarted.set(false)
                return
            }
            
            // Check microphone permission
            if (ContextCompat.checkSelfPermission(ctx, Manifest.permission.RECORD_AUDIO) 
                != PackageManager.PERMISSION_GRANTED) {
                Log.e(TAG, "RECORD_AUDIO permission not granted")
                isStarted.set(false)
                return
            }
            
            startListening()
        }
    }
    
    private fun startListening() {
        val ctx = context ?: run {
            Log.e(TAG, "Context is null in startListening")
            return
        }
        
        // Start SpeechRecognizer intent
        try {
            val intent = android.content.Intent(android.speech.RecognizerIntent.ACTION_RECOGNIZE_SPEECH)
            intent.putExtra(android.speech.RecognizerIntent.EXTRA_LANGUAGE_MODEL, android.speech.RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            intent.putExtra(android.speech.RecognizerIntent.EXTRA_LANGUAGE, "en-US")
            intent.putExtra(android.speech.RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            intent.putExtra(android.speech.RecognizerIntent.EXTRA_MAX_RESULTS, 1)
            
            speechRecognizer?.startListening(intent)
            Log.d(TAG, "SpeechRecognizer startListening called")
        } catch (e: Exception) {
            Log.e(TAG, "Error starting SpeechRecognizer", e)
        }
    }
    
    fun appendPCMData(pcmData: ByteArray) {
        // Don't process audio if recognition is not started or is stopping
        if (!isStarted.get() || isStopping.get()) {
            // Silently ignore - recognition is not active
            return
        }
        
        // Try Google Cloud Speech-to-Text first (if initialized)
        if (GoogleCloudSpeechService.instance.isInitialized()) {
            // Check if Google Cloud service is stopped before trying to append
            // This prevents unnecessary processing and logging
            if (GoogleCloudSpeechService.instance.isStopped()) {
                // Silently ignore - recognition has been stopped and final result obtained
                return
            }
            
            // Always buffer audio even if not streaming yet - it will be processed when ready
            GoogleCloudSpeechService.instance.appendPCMData(pcmData)
            if (GoogleCloudSpeechService.instance.isStreaming()) {
                Log.d(TAG, "Sent PCM data to Google Cloud Speech: ${pcmData.size} bytes (streaming)")
            } else {
                Log.d(TAG, "Buffered PCM data to Google Cloud Speech: ${pcmData.size} bytes (not streaming yet - will process when ready)")
            }
        } else {
            // Fallback: Android SpeechRecognizer uses its own audio capture
            // PCM data from Bluetooth cannot be processed directly
            Log.d(TAG, "Received Bluetooth PCM data: ${pcmData.size} bytes (Google Cloud not initialized, using phone mic)")
        }
    }
    
    fun stopRecognition() {
        if (!isStarted.get()) {
            Log.w(TAG, "Recognition not started")
            return
        }
        
        // Mark as stopping to prevent new sessions from starting
        isStopping.set(true)
        isStarted.set(false)
        
        // Stop the appropriate service
        if (usingGoogleCloud) {
            // Stop Google Cloud Speech - MUST wait for completion to prevent starting new session too early
            // Use runBlocking on IO dispatcher to ensure network operations happen on background thread
            // This ensures the transcription is fully processed before allowing a new session to start
            kotlinx.coroutines.runBlocking(Dispatchers.IO) {
                try {
                    val finalText = GoogleCloudSpeechService.instance.stopRecognition()
                    Log.d(TAG, "Google Cloud Speech stopped - Final text: '$finalText'")
                    // Results are already sent to Flutter by GoogleCloudSpeechService
                } catch (e: Exception) {
                    Log.e(TAG, "Error stopping Google Cloud Speech: ${e.message}", e)
                } finally {
                    // Clear stopping flag after stop is complete
                    isStopping.set(false)
                }
            }
            usingGoogleCloud = false
        } else {
            // Stop Android SpeechRecognizer
            speechRecognizer?.cancel()
            
            val finalText = recognitionResults.toString().trim()
            Log.d(TAG, "Stop recognition - Final text: '$finalText'")
            
            // Send results to Flutter
            BleChannelHelper.bleSpeechRecognize(mapOf("script" to if (finalText.isEmpty()) "" else finalText))
            
            // Clear stopping flag
            isStopping.set(false)
        }
    }
    
    /**
     * Check if recognition is currently active (started and not stopped)
     * This can be used to determine if logging should occur
     */
    fun isRecognitionActive(): Boolean {
        if (!isStarted.get() || isStopping.get()) {
            return false
        }
        // Also check if Google Cloud is stopped (if using it)
        if (usingGoogleCloud && com.example.demo_ai_even.speech.GoogleCloudSpeechService.instance.isStopped()) {
            return false
        }
        return true
    }
}

