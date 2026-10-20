package com.magnatrus.doc2pdf

import android.app.Activity
import android.graphics.Color
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.print.PrintAttributes
import android.print.SilentPdfPrinter
import android.util.Base64
import android.view.ViewGroup
import android.webkit.JavascriptInterface
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.webkit.WebViewAssetLoader
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.apache.poi.hwpf.HWPFDocument
import org.apache.poi.hwpf.converter.PicturesManager
import org.apache.poi.hwpf.converter.WordToHtmlConverter
import org.apache.poi.hwpf.extractor.WordExtractor
import org.apache.poi.hwpf.usermodel.PictureType
import java.io.ByteArrayInputStream
import java.io.File
import java.io.FileInputStream
import java.io.StringWriter
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.zip.ZipFile
import javax.xml.parsers.DocumentBuilderFactory
import javax.xml.transform.OutputKeys
import javax.xml.transform.TransformerFactory
import javax.xml.transform.dom.DOMSource
import javax.xml.transform.stream.StreamResult

/**
 * Renders .docx / .doc to PDF entirely offline, with no system print dialog.
 *
 * .docx -> docx-preview running inside an offscreen WebView, printed through the
 *          WebView's own PrintDocumentAdapter (driven by SilentPdfPrinter).
 * .doc  -> Apache POI (HWPF) -> HTML -> same offscreen WebView.
 */
class RenderPdfPlugin(
    flutterEngine: FlutterEngine,
    private val activity: Activity,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    private companion object {
        const val METHOD_CHANNEL = "doc2pdf/render"
        const val EVENT_CHANNEL = "doc2pdf/progress"
        const val ORIGIN = "https://appassets.androidplatform.net/"
        const val INDEX_URL = ORIGIN + "assets/word/index.html"
        const val LOCAL_DOC_URL = ORIGIN + "localdoc/doc"
    }

    private enum class Format(val label: String) { DOCX("docx"), DOC("doc"), UNKNOWN("unknown") }

    private data class Request(
        val sourceFile: File,
        val outputPath: String,
        val pageWidthMils: Int,
        val pageHeightMils: Int,
        val colorMode: String,
        val jobName: String,
        val format: Format,
        val startedAt: Long,
    )

    private val messenger = flutterEngine.dartExecutor.binaryMessenger
    private val methodChannel = MethodChannel(messenger, METHOD_CHANNEL)
    private val eventChannel = EventChannel(messenger, EVENT_CHANNEL)
    private val main = Handler(Looper.getMainLooper())

    /** Copying the finished PDF into shared Documents must never block the main thread. */
    private val publisherExecutor: ExecutorService = Executors.newSingleThreadExecutor()

    private var events: EventChannel.EventSink? = null
    private var webView: WebView? = null
    private var onPageReady: (() -> Unit)? = null
    private var servedFile: File? = null
    private var tempHtmlFile: File? = null

    private var pendingRequest: Request? = null
    private var pendingResult: MethodChannel.Result? = null

    private val assetLoader: WebViewAssetLoader by lazy {
        WebViewAssetLoader.Builder()
            .setDomain("appassets.androidplatform.net")
            .addPathHandler("/assets/", WebViewAssetLoader.AssetsPathHandler(activity))
            .addPathHandler("/localdoc/", WebViewAssetLoader.PathHandler { path -> serveLocal(path) })
            .build()
    }

    init {
        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(this)
    }

    // ---------------------------------------------------------------- channel

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "convert" -> handleConvert(call, result)
            "dispose" -> {
                releaseWebView()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
        events = sink
    }

    override fun onCancel(arguments: Any?) {
        events = null
    }

    private fun handleConvert(call: MethodCall, result: MethodChannel.Result) {
        if (pendingRequest != null) {
            result.error("busy", "A conversion is already in progress", null)
            return
        }

        val sourcePath = call.argument<String>("sourcePath")
        val outputPath = call.argument<String>("outputPath")
        if (sourcePath.isNullOrBlank() || outputPath.isNullOrBlank()) {
            result.error("bad_args", "sourcePath and outputPath are required", null)
            return
        }

        val sourceFile = File(sourcePath)
        if (!sourceFile.exists() || !sourceFile.isFile) {
            result.error("file_not_found", "Source file does not exist: $sourcePath", null)
            return
        }

        emitProgress("detecting", 2)

        val format = detectFormat(sourceFile)
        if (format == Format.UNKNOWN) {
            result.error(
                "unsupported_format",
                "Only Word .docx and .doc files are supported",
                null,
            )
            return
        }

        val request = Request(
            sourceFile = sourceFile,
            outputPath = outputPath,
            pageWidthMils = (call.argument<Any>("pageWidthMils") as? Number)?.toInt() ?: 8268,
            pageHeightMils = (call.argument<Any>("pageHeightMils") as? Number)?.toInt() ?: 11693,
            colorMode = call.argument<String>("colorMode") ?: "color",
            jobName = call.argument<String>("jobName") ?: sourceFile.nameWithoutExtension,
            format = format,
            startedAt = System.currentTimeMillis(),
        )

        pendingRequest = request
        pendingResult = result

        // API 26-28 only: publishing into public Documents needs the legacy
        // storage permission. Requested here so it is granted by the time the
        // PDF is ready; Android 10+ never prompts.
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            (activity as? MainActivity)?.requestLegacyWritePermission()
        }

        beginRender(request)
    }

    // ------------------------------------------------------------- rendering

    private fun beginRender(request: Request) {
        val webView = ensureWebView(request)

        onPageReady = {
            // Must be queued before the render call: configurePage() sets the
            // CSS viewport and the px-based @page size used by the print box.
            evaluate("window.configurePage(${request.pageWidthMils}, ${request.pageHeightMils})")
            when (request.format) {
                Format.DOCX -> {
                    servedFile = request.sourceFile
                    evaluate("window.renderFromUrl('$LOCAL_DOC_URL')")
                }
                Format.DOC -> renderLegacyDoc(request)
                Format.UNKNOWN -> failConversion("unsupported_format", "Unsupported format")
            }
        }

        webView.loadUrl(INDEX_URL)
    }

    /** Legacy .doc: convert to HTML off the main thread, then hand it to the WebView. */
    private fun renderLegacyDoc(request: Request) {
        emitProgress("parsing", 15)
        Thread(
            {
                val html = try {
                    LegacyDocConverter.toHtml(request.sourceFile)
                } catch (t: Throwable) {
                    null
                }
                main.post {
                    if (html == null) {
                        failConversion(
                            "doc_parse_failed",
                            "Could not read this legacy .doc file. It may be corrupt or password-protected.",
                        )
                        return@post
                    }
                    val htmlFile = File(activity.cacheDir, "doc2pdf_legacy.html")
                    htmlFile.writeText(html, Charsets.UTF_8)
                    tempHtmlFile = htmlFile
                    servedFile = htmlFile
                    evaluate("window.renderHtmlFromUrl('$LOCAL_DOC_URL')")
                }
            },
            "doc2pdf-legacy",
        ).start()
    }

    private fun ensureWebView(request: Request): WebView {
        webView?.let { return it }

        val widthPx = milsToPx(request.pageWidthMils)
        val heightPx = milsToPx(request.pageHeightMils)

        val wv = WebView(activity)
        wv.settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = true
            allowFileAccess = false
            allowContentAccess = false
            cacheMode = WebSettings.LOAD_NO_CACHE
            // Keep the CSS viewport at the document width set by configurePage.
            // Overview mode zooms out and can make the print box narrower than
            // the fixed-width page, which clips both sides of the PDF.
            loadWithOverviewMode = false
            useWideViewPort = true
            textZoom = 100
        }
        wv.setBackgroundColor(Color.WHITE)
        wv.isVerticalScrollBarEnabled = false
        wv.isHorizontalScrollBarEnabled = false
        wv.addJavascriptInterface(JsBridge(), "AndroidBridge")
        wv.webViewClient = object : WebViewClient() {
            override fun shouldInterceptRequest(
                view: WebView?,
                request: WebResourceRequest?,
            ): WebResourceResponse? {
                val url = request?.url ?: return null
                if (url.host == "appassets.androidplatform.net") {
                    return assetLoader.shouldInterceptRequest(url)
                }
                // Let the WebView handle its own inline resources. Returning an
                // empty response for these breaks base64 image data emitted by
                // docx-preview (and therefore every DOCX-embedded image).
                when (url.scheme?.lowercase()) {
                    "data", "blob", "about", "file" -> return null
                }
                // Hard offline guarantee: nothing outside the bundled assets loads.
                return WebResourceResponse("text/plain", "utf-8", ByteArrayInputStream(ByteArray(0)))
            }

            override fun onPageFinished(view: WebView?, url: String?) {
                val action = onPageReady
                onPageReady = null
                action?.invoke()
            }
        }

        val root = activity.findViewById<ViewGroup>(android.R.id.content)
        val params = ViewGroup.LayoutParams(widthPx, heightPx)
        root.addView(wv, params)
        wv.translationX = -1_000_000f
        wv.translationY = -1_000_000f

        webView = wv
        return wv
    }

    private fun evaluate(script: String) {
        webView?.evaluateJavascript(script, null)
    }

    // ---------------------------------------------------------------- printing

    private fun onRenderComplete(pageCount: Int) {
        val request = pendingRequest ?: return
        val wv = webView ?: return

        emitProgress("printing", 96)

        val adapter = wv.createPrintDocumentAdapter(request.jobName)
        val attributes = PrintAttributes.Builder()
            .setMediaSize(
                PrintAttributes.MediaSize(
                    "doc2pdf",
                    "doc2pdf",
                    request.pageWidthMils,
                    request.pageHeightMils,
                ),
            )
            .setResolution(PrintAttributes.Resolution("doc2pdf", "doc2pdf", 300, 300))
            .setMinMargins(PrintAttributes.Margins.NO_MARGINS)
            .setColorMode(
                if (request.colorMode == "mono") {
                    PrintAttributes.COLOR_MODE_MONOCHROME
                } else {
                    PrintAttributes.COLOR_MODE_COLOR
                },
            )
            .build()

        SilentPdfPrinter(request.outputPath).print(
            adapter,
            attributes,
            object : SilentPdfPrinter.Callback {
                override fun onSuccess(file: File, pages: Int) {
                    emitProgress("printing", 98)

                    val resolvedPages = if (pages > 0) pages else pageCount
                    val sizeBytes = file.length()
                    val durationMs = System.currentTimeMillis() - request.startedAt
                    val formatLabel = request.format.label

                    // Publish a copy into shared storage off the main thread; a
                    // failure there degrades to a warning, never a failed conversion.
                    publisherExecutor.execute {
                        val published = try {
                            DocumentPublisher(activity.applicationContext)
                                .publish(file, file.name)
                        } catch (t: Throwable) {
                            // Never leave the Dart side waiting on a failed publish.
                            DocumentPublisher.Published(
                                failure = "Could not save the PDF into shared storage",
                            )
                        }
                        main.post {
                            emitProgress("done", 100)
                            val payload = hashMapOf<String, Any>(
                                "outputPath" to file.absolutePath,
                                "pageCount" to resolvedPages,
                                "format" to formatLabel,
                                "sizeBytes" to sizeBytes,
                                "durationMs" to durationMs,
                            )
                            published.location?.let { payload["savedLocation"] = it }
                            published.displayName?.let { payload["savedName"] = it }
                            published.path?.let { payload["savedPath"] = it }
                            published.failure?.let { payload["saveWarning"] = it }
                            finishSuccess(payload)
                        }
                    }
                }

                override fun onFailure(error: String) {
                    failConversion("print_failed", error)
                }
            },
        )
    }

    // -------------------------------------------------------------- lifecycle

    private fun finishSuccess(payload: Map<String, Any>) {
        val result = pendingResult
        clearPending()
        result?.success(payload)
    }

    private fun failConversion(code: String, message: String) {
        val result = pendingResult
        clearPending()
        result?.error(code, message, null)
    }

    private fun clearPending() {
        pendingRequest = null
        pendingResult = null
        servedFile = null
        tempHtmlFile?.delete()
        tempHtmlFile = null
        onPageReady = null
    }

    private fun emitProgress(phase: String, percent: Int) {
        val payload = hashMapOf<String, Any>("phase" to phase, "percent" to percent)
        main.post { events?.success(payload) }
    }

    fun dispose() {
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        publisherExecutor.shutdown()
        releaseWebView()
    }

    private fun releaseWebView() {
        val wv = webView ?: return
        webView = null
        try {
            (wv.parent as? ViewGroup)?.removeView(wv)
            wv.loadUrl("about:blank")
            wv.removeJavascriptInterface("AndroidBridge")
            wv.destroy()
        } catch (_: Throwable) {
        }
    }

    // ------------------------------------------------------------------- util

    private fun serveLocal(path: String): WebResourceResponse {
        val file = servedFile
            ?: return WebResourceResponse("text/plain", "utf-8", ByteArrayInputStream(ByteArray(0)))
        if (!file.exists()) {
            return WebResourceResponse("text/plain", "utf-8", 404, "Not Found", emptyMap(), null)
        }
        val mime = when {
            path.endsWith(".html") -> "text/html"
            path.endsWith(".docx") -> "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
            else -> "application/octet-stream"
        }
        val headers = mapOf(
            "Content-Type" to mime,
            "Cache-Control" to "no-store",
        )
        return WebResourceResponse(mime, null, 200, "OK", headers, FileInputStream(file))
    }

    private fun detectFormat(file: File): Format {
        val header = ByteArray(8)
        val read = FileInputStream(file).use { it.read(header) }
        if (read < 4) return Format.UNKNOWN

        val isZip = header[0] == 0x50.toByte() &&
            header[1] == 0x4B.toByte() &&
            (header[2] == 0x03.toByte() || header[2] == 0x05.toByte() || header[2] == 0x07.toByte())

        if (isZip) {
            return if (zipContains(file, "word/document.xml") || zipContains(file, "word/document2.xml")) {
                Format.DOCX
            } else {
                Format.UNKNOWN
            }
        }

        val isOle2 = read >= 8 &&
            header[0] == 0xD0.toByte() && header[1] == 0xCF.toByte() &&
            header[2] == 0x11.toByte() && header[3] == 0xE0.toByte() &&
            header[4] == 0xA1.toByte() && header[5] == 0xB1.toByte() &&
            header[6] == 0x1A.toByte() && header[7] == 0xE1.toByte()

        return if (isOle2) Format.DOC else Format.UNKNOWN
    }

    private fun zipContains(file: File, entry: String): Boolean = try {
        ZipFile(file).use { it.getEntry(entry) != null }
    } catch (_: Throwable) {
        false
    }

    private fun milsToPx(mils: Int): Int = ((mils / 1000.0) * 96.0).toInt().coerceIn(200, 4000)

    /** Called from the WebView's JavaScript thread; everything is marshalled to main. */
    private inner class JsBridge {
        @JavascriptInterface
        fun onProgress(phase: String, percent: Double) {
            val value = percent.toInt().coerceIn(0, 100)
            main.post { events?.success(hashMapOf("phase" to phase, "percent" to value)) }
        }

        @JavascriptInterface
        fun onRendered(pages: Int) {
            main.post { onRenderComplete(pages) }
        }

        @JavascriptInterface
        fun onError(message: String) {
            main.post { failConversion("render_failed", message) }
        }
    }

    // ------------------------------------------------------------ legacy .doc

    private object LegacyDocConverter {
        fun toHtml(file: File): String {
            return try {
                FileInputStream(file).use { input ->
                    val document = HWPFDocument(input)
                    val factory = DocumentBuilderFactory.newInstance().apply {
                        isNamespaceAware = true
                    }
                    val dom = factory.newDocumentBuilder().newDocument()
                    val converter = WordToHtmlConverter(dom)
                    converter.setPicturesManager(object : PicturesManager {
                        override fun savePicture(
                            picture: ByteArray,
                            pictureType: PictureType,
                            suggestedName: String,
                            widthInches: Float,
                            heightInches: Float,
                        ): String {
                            val mime = pictureType.mime ?: "image/png"
                            val data = Base64.encodeToString(picture, Base64.NO_WRAP)
                            return "data:$mime;base64,$data"
                        }
                    })
                    converter.processDocument(document)

                    val transformer = TransformerFactory.newInstance().newTransformer()
                    transformer.setOutputProperty(OutputKeys.METHOD, "html")
                    transformer.setOutputProperty(OutputKeys.OMIT_XML_DECLARATION, "yes")
                    val writer = StringWriter()
                    transformer.transform(DOMSource(converter.document), StreamResult(writer))
                    writer.toString()
                }
            } catch (_: Throwable) {
                plainTextFallback(file)
            }
        }

        private fun plainTextFallback(file: File): String {
            FileInputStream(file).use { input ->
                val text = WordExtractor(input).use { it.text }
                val body = text.split("\n").joinToString("") { line ->
                    "<p>${escape(line)}</p>"
                }
                return "<div style=\"font-family:'Calibri',sans-serif;font-size:11pt\">$body</div>"
            }
        }

        private fun escape(value: String): String = value
            .replace("&", "&amp;")
            .replace("<", "&lt;")
            .replace(">", "&gt;")
    }
}
