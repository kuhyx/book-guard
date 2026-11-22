package com.kuhy.book_guard_app

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.googlecode.tesseract.android.TessBaseAPI
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors

/**
 * Tesseract on the phone, for `page_reader_tesseract.dart`.
 *
 * One method, `recognize(jpeg, psm, model)`: reads the JPEG [jpeg] and
 * returns its lines, each a list of words `{text, left, top, right, bottom,
 * conf}` (confidence 0-1) in the image's own pixels. Recognition runs on
 * worker threads, one engine each (TessBaseAPI is not thread-safe and takes
 * seconds), never on the UI thread.
 */
class TesseractChannel(
    private val context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {
    // The fast model reads the four turns of a photo at once, one engine per
    // thread (TessBaseAPI is not thread-safe): a sideways page no longer
    // waits for each wrong turn in turn. The full model is a rare second
    // opinion: one thread, one engine.
    private val fastPool = Executors.newFixedThreadPool(FAST_THREADS)
    private val fullWorker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val engines = ThreadLocal.withInitial { HashMap<String, TessBaseAPI>() }

    init {
        MethodChannel(messenger, "book_guard/tesseract").setMethodCallHandler(this)
        warmUp()
    }

    /**
     * Loads the fast model into every pool thread's engine at app start, so
     * the first photo's four turns do not each wait for an init. The latch
     * holds each task until all have started: one per thread, not two on one.
     */
    private fun warmUp() {
        val started = CountDownLatch(FAST_THREADS)
        repeat(FAST_THREADS) {
            fastPool.execute {
                started.countDown()
                started.await()
                try {
                    engine("fast")
                } catch (e: IllegalStateException) {
                    Log.w("book_guard", "tesseract warm-up failed", e)
                }
            }
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "recognize" -> onRecognize(call, result)
            else -> result.notImplemented()
        }
    }

    private fun onRecognize(call: MethodCall, result: MethodChannel.Result) {
        val jpeg = call.argument<ByteArray>("jpeg")
        val psm = call.argument<Int>("psm") ?: TessBaseAPI.PageSegMode.PSM_AUTO
        val model = call.argument<String>("model") ?: "fast"
        if (jpeg == null) {
            result.error("args", "jpeg is required", null)
            return
        }
        val worker = if (model == "full") fullWorker else fastPool
        worker.execute {
            try {
                val lines = recognize(jpeg, psm, model)
                main.post { result.success(lines) }
            } catch (e: Exception) {
                main.post { result.error("tesseract", e.message, null) }
            }
        }
    }

    /**
     * The eng model of [model] ("fast", or "full": the bigger one, a second
     * opinion), copied out of the APK's assets once (Tesseract wants a file
     * at `<root>/tessdata/eng.traineddata`).
     */
    @Synchronized
    private fun tessdataRoot(model: String): String {
        val root = if (model == "full") File(context.filesDir, "full") else context.filesDir
        val dir = File(root, "tessdata")
        val target = File(dir, "eng.traineddata")
        val asset = if (model == "full") "tessdata_full" else "tessdata"
        val bundled = context.assets.open("$asset/eng.traineddata").use { it.readBytes() }
        if (!target.exists() || target.length() != bundled.size.toLong()) {
            dir.mkdirs()
            target.writeBytes(bundled)
        }
        return root.absolutePath
    }

    private fun engine(model: String): TessBaseAPI =
        engines.get()!!.getOrPut(model) {
            TessBaseAPI().also {
                check(it.init(tessdataRoot(model), "eng", TessBaseAPI.OEM_LSTM_ONLY)) {
                    "tesseract init failed"
                }
            }
        }

    private fun recognize(
        jpeg: ByteArray,
        psm: Int,
        model: String,
    ): List<List<Map<String, Any>>> {
        val tess = engine(model)
        tess.pageSegMode = psm
        // A JPEG file Leptonica reads: handed raw grey pixels, Tesseract
        // missed small page numbers it reads this way (page_truth, 2026-11-22).
        val file = File.createTempFile("ink", ".jpg", context.cacheDir)
        try {
            file.writeBytes(jpeg)
            tess.setImage(file)
        } finally {
            file.delete()
        }
        // The iterator only has a page to walk once something has recognised it.
        tess.getUTF8Text()
        val lines = ArrayList<List<Map<String, Any>>>()
        val iterator = tess.resultIterator
        if (iterator != null) {
            val level = TessBaseAPI.PageIteratorLevel.RIL_WORD
            val lineLevel = TessBaseAPI.PageIteratorLevel.RIL_TEXTLINE
            var words = ArrayList<Map<String, Any>>()
            iterator.begin()
            do {
                val text = iterator.getUTF8Text(level)?.trim().orEmpty()
                val box = iterator.getBoundingRect(level)
                if (text.isNotEmpty()) {
                    words.add(
                        mapOf(
                            "text" to text,
                            "left" to box.left,
                            "top" to box.top,
                            "right" to box.right,
                            "bottom" to box.bottom,
                            "conf" to iterator.confidence(level) / 100.0,
                        ),
                    )
                }
                if (iterator.isAtFinalElement(lineLevel, level)) {
                    if (words.isNotEmpty()) lines.add(words)
                    words = ArrayList()
                }
            } while (iterator.next(level))
            iterator.delete()
        }
        tess.clear()
        return lines
    }

    private companion object {
        const val FAST_THREADS = 4
    }
}
