package com.kuhy.book_guard_app

import android.content.Context
import android.os.Handler
import android.os.Looper
import com.googlecode.tesseract.android.TessBaseAPI
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

/**
 * Tesseract on the phone, for `page_reader_tesseract.dart`.
 *
 * One method, `recognize(path, psm, model)`: reads the image file at [path] and
 * returns its lines, each a list of words `{text, left, top, right, bottom,
 * conf}` (confidence 0-1) in the image's own pixels. Recognition runs on a
 * single worker thread (TessBaseAPI is not thread-safe and takes seconds),
 * never on the UI thread.
 */
class TesseractChannel(
    private val context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val engines = HashMap<String, TessBaseAPI>()

    init {
        MethodChannel(messenger, "book_guard/tesseract").setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "recognize") {
            result.notImplemented()
            return
        }
        val path = call.argument<String>("path")
        val psm = call.argument<Int>("psm") ?: TessBaseAPI.PageSegMode.PSM_AUTO
        val model = call.argument<String>("model") ?: "fast"
        if (path == null) {
            result.error("args", "path is required", null)
            return
        }
        worker.execute {
            try {
                val lines = recognize(path, psm, model)
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
        engines.getOrPut(model) {
            TessBaseAPI().also {
                check(it.init(tessdataRoot(model), "eng", TessBaseAPI.OEM_LSTM_ONLY)) {
                    "tesseract init failed"
                }
            }
        }

    private fun recognize(path: String, psm: Int, model: String): List<List<Map<String, Any>>> {
        val tess = engine(model)
        tess.pageSegMode = psm
        tess.setImage(File(path))
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
}
