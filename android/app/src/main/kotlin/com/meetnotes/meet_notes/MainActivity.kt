package com.meetnotes.meet_notes

import android.graphics.BitmapFactory
import com.google.mlkit.common.model.DownloadConditions
import com.google.mlkit.common.model.RemoteModelManager
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.digitalink.DigitalInkRecognition
import com.google.mlkit.vision.digitalink.DigitalInkRecognitionModel
import com.google.mlkit.vision.digitalink.DigitalInkRecognitionModelIdentifier
import com.google.mlkit.vision.digitalink.DigitalInkRecognizerOptions
import com.google.mlkit.vision.digitalink.Ink
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "meet_notes/ocr")
            .setMethodCallHandler { call, result ->
                if (call.method == "recognizeHandwriting") {
                    val pngBytes = call.argument<ByteArray>("pngBytes")
                    @Suppress("UNCHECKED_CAST")
                    val rawStrokes = call.argument<List<List<Map<String, Number>>>>("strokes")
                    val language = call.argument<String>("language") ?: "tr-TR"
                    val baseLang = language.split("-", "_").firstOrNull()?.lowercase() ?: "tr"

                    recognizeOnAndroid(pngBytes, rawStrokes, baseLang, result)
                } else {
                    result.notImplemented()
                }
            }
    }

    private fun recognizeOnAndroid(
        pngBytes: ByteArray?,
        rawStrokes: List<List<Map<String, Number>>>?,
        langTag: String,
        result: MethodChannel.Result
    ) {
        if (!rawStrokes.isNullOrEmpty()) {
            val modelId = DigitalInkRecognitionModelIdentifier.fromLanguageTag(langTag)
                ?: DigitalInkRecognitionModelIdentifier.fromLanguageTag("en")

            if (modelId != null) {
                val model = DigitalInkRecognitionModel.builder(modelId).build()
                val remoteModelManager = RemoteModelManager.getInstance()
                val ink = buildInk(rawStrokes)

                remoteModelManager.isModelDownloaded(model)
                    .addOnSuccessListener { isDownloaded ->
                        if (isDownloaded) {
                            runDigitalInk(model, ink, pngBytes, result)
                        } else {
                            remoteModelManager.download(model, DownloadConditions.Builder().build())
                                .addOnSuccessListener {
                                    runDigitalInk(model, ink, pngBytes, result)
                                }
                                .addOnFailureListener {
                                    runFallbackBitmapOcr(pngBytes, result)
                                }
                        }
                    }
                    .addOnFailureListener {
                        runFallbackBitmapOcr(pngBytes, result)
                    }
                return
            }
        }
        runFallbackBitmapOcr(pngBytes, result)
    }

    private fun buildInk(rawStrokes: List<List<Map<String, Number>>>): Ink {
        val inkBuilder = Ink.builder()
        for (strokePoints in rawStrokes) {
            if (strokePoints.isEmpty()) continue
            val strokeBuilder = Ink.Stroke.builder()
            for (pt in strokePoints) {
                val x = pt["x"]?.toFloat() ?: 0f
                val y = pt["y"]?.toFloat() ?: 0f
                val t = pt["t"]?.toLong() ?: 0L
                strokeBuilder.addPoint(Ink.Point.create(x, y, t))
            }
            inkBuilder.addStroke(strokeBuilder.build())
        }
        return inkBuilder.build()
    }

    private fun runDigitalInk(
        model: DigitalInkRecognitionModel,
        ink: Ink,
        pngBytes: ByteArray?,
        result: MethodChannel.Result
    ) {
        val recognizer = DigitalInkRecognition.getClient(
            DigitalInkRecognizerOptions.builder(model).build()
        )
        recognizer.recognize(ink)
            .addOnSuccessListener { recognitionResult ->
                val text = recognitionResult.candidates.firstOrNull()?.text?.trim().orEmpty()
                if (text.isNotEmpty()) {
                    result.success(mapOf("text" to text, "engine" to "ML Kit Digital Ink"))
                } else {
                    runFallbackBitmapOcr(pngBytes, result)
                }
            }
            .addOnFailureListener {
                runFallbackBitmapOcr(pngBytes, result)
            }
    }

    private fun runFallbackBitmapOcr(
        pngBytes: ByteArray?,
        result: MethodChannel.Result
    ) {
        if (pngBytes == null || pngBytes.isEmpty()) {
            result.error("OCR_FAILED", "El yazısı görüntüsü bulunamadı.", null)
            return
        }
        val bitmap = BitmapFactory.decodeByteArray(pngBytes, 0, pngBytes.size)
        if (bitmap == null) {
            result.error("DECODE_FAILED", "PNG görüntüsü çözümlenemedi.", null)
            return
        }
        val image = InputImage.fromBitmap(bitmap, 0)
        val recognizer = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
        recognizer.process(image)
            .addOnSuccessListener { visionText ->
                result.success(
                    mapOf(
                        "text" to visionText.text.trim(),
                        "engine" to "ML Kit OCR"
                    )
                )
            }
            .addOnFailureListener { e ->
                result.error("OCR_ERROR", e.localizedMessage ?: "OCR başarısız.", null)
            }
    }
}
