package android.print

import android.os.CancellationSignal
import android.os.ParcelFileDescriptor
import java.io.File
import java.io.IOException

/**
 * Drives a [PrintDocumentAdapter] directly, bypassing [android.print.PrintManager],
 * so no system print UI is ever shown. Lives in the `android.print` package because
 * [PrintDocumentAdapter.LayoutResultCallback] / [WriteResultCallback] have
 * package-private constructors.
 *
 * All callbacks are delivered on the thread that invokes [print] (the main thread),
 * which is required by the WebView adapter (it needs a Looper).
 */
class SilentPdfPrinter(private val outputPath: String) {

    interface Callback {
        fun onSuccess(file: File, pageCount: Int)
        fun onFailure(error: String)
    }

    fun print(
        adapter: PrintDocumentAdapter,
        attributes: PrintAttributes,
        callback: Callback,
    ) {
        val outFile = File(outputPath)
        outFile.parentFile?.let { if (!it.exists()) it.mkdirs() }
        if (outFile.exists()) outFile.delete()

        var finished = false
        var pageCount = 1
        var pfd: ParcelFileDescriptor? = null

        val fail: (String) -> Unit = { message ->
            if (!finished) {
                finished = true
                try {
                    pfd?.close()
                } catch (_: IOException) {
                }
                pfd = null
                callback.onFailure(message)
            }
        }

        val layoutCallback = object : PrintDocumentAdapter.LayoutResultCallback() {
            override fun onLayoutFinished(info: PrintDocumentInfo?, changed: Boolean) {
                val pages = info?.pageCount ?: 0
                pageCount = if (pages <= 0) 1 else pages

                val descriptor = try {
                    ParcelFileDescriptor.open(
                        outFile,
                        ParcelFileDescriptor.MODE_CREATE or
                            ParcelFileDescriptor.MODE_READ_WRITE or
                            ParcelFileDescriptor.MODE_TRUNCATE,
                    )
                } catch (e: IOException) {
                    fail("Cannot open output file: ${e.message}")
                    return
                }
                pfd = descriptor

                val writeCallback = object : PrintDocumentAdapter.WriteResultCallback() {
                    override fun onWriteFinished(pages: Array<out PageRange>?) {
                        if (finished) return
                        finished = true
                        try {
                            pfd?.close()
                        } catch (_: IOException) {
                        }
                        pfd = null

                        if (!outFile.exists() || outFile.length() == 0L) {
                            callback.onFailure("Printer produced an empty PDF")
                        } else {
                            callback.onSuccess(outFile, pageCount)
                        }
                    }

                    override fun onWriteFailed(error: CharSequence?) {
                        fail("Write failed: ${error ?: "unknown"}")
                    }

                    override fun onWriteCancelled() {
                        fail("Write cancelled")
                    }
                }

                adapter.onWrite(
                    arrayOf(PageRange.ALL_PAGES),
                    descriptor,
                    CancellationSignal(),
                    writeCallback,
                )
            }

            override fun onLayoutFailed(error: CharSequence?) {
                fail("Layout failed: ${error ?: "unknown"}")
            }

            override fun onLayoutCancelled() {
                fail("Layout cancelled")
            }
        }

        adapter.onLayout(null, attributes, CancellationSignal(), layoutCallback, null)
    }
}
