# doc2pdf — Architecture

Companion to [`plan.md`](./plan.md) and [`design.md`](./design.md).

---

## 1. System Overview

`doc2pdf` is an Android-only Flutter app that converts Word documents to PDF **entirely on-device**. The rendering of Word layout is delegated to a bundled JavaScript engine (`docx-preview`) running inside an offscreen native `WebView`; PDF emission is delegated to Android's own print framework driven silently.

```text
┌──────────────────────────────────────────────────────────────────────┐
│                          Flutter (Dart) UI Layer                       │
│  converter_screen · result_screen · widgets · Riverpod providers       │
└───────────────▲───────────────────────────────────────────▲──────────┘
                │ MethodChannel("doc2pdf/render")           │ EventChannel("doc2pdf/progress")
                │ convertToPdf / cancel                      │ ConversionStage
┌───────────────┴───────────────────────────────────────────┴──────────┐
│                       Android Platform Layer (Kotlin)                  │
│                                                                        │
│   RenderPdfPlugin                                                      │
│   ├─ sniff header (PK zip vs OLE2)                                     │
│   ├─ .docx ──► offscreen WebView ──► docx-preview (JS) ──┐             │
│   ├─ .doc  ──► Apache POI HWPF ──► HTML ─────────────────┤             │
│   │                                                       ▼             │
│   │                                          paginated HTML w/ geometry │
│   └─ webView.createPrintDocumentAdapter()                              │
│                     │                                                  │
│                     ▼                                                  │
│        android.print.SilentPdfPrinter  (same package as SDK internals)│
│                     │                                                  │
│                     ▼                                                  │
│              PdfDocument  ──►  .pdf file (cacheDir)                    │
└───────────────────────────────────────────────────────────────────────┘
```

**Key property:** the source document **never leaves the device**, and the render WebView is fully offline (assets served from `WebViewAssetLoader`, no network stack). The only network consumer in the app is the AdMob SDK, which is isolated from the render/print pipeline.

---

## 2. Layer Responsibilities

| Layer | Owns | Never does |
|---|---|---|
| **Dart UI** | screens, theming, state, file pick, share/save orchestration | HTML parsing, WebView, print |
| **Dart services** | thin typed wrappers over Method/Event channels | business logic |
| **Kotlin plugin** | format sniffing, WebView lifecycle, POI, print orchestration | UI |
| **JS (`index.html`)** | docx-preview invocation, font registration, layout settle signal | file I/O beyond `fetch` |
| **`android.print` bridge** | silent `PrintDocumentAdapter` lifecycle | anything format-specific |
| **AdMob SDK** | banner + interstitial delivery, UMP consent | touching documents, files, or render state |

---

## 3. Component Detail

### 3.1 `RenderPdfPlugin.kt` (Kotlin)

Responsibilities:
1. Register `MethodChannel("doc2pdf/render")` and `EventChannel("doc2pdf/progress")`.
2. **Sniff** the source header:
   - `.docx` → `50 4B 03 04` (`PK\x03\x04`, ZIP)
   - `.doc` → `D0 CF 11 E0 A1 B1 1A E1` (OLE2/CFB)
   - else → `unsupported_format`
3. Route:
   - **`.docx`**: build an offscreen `WebView`, load `index.html`, provide the file via `WebViewAssetLoader`, `evaluateJavascript` the render call, await `AndroidBridge.onRendered`.
   - **`.doc`**: parse with POI (see §3.4) into HTML, then feed the **same** WebView/print path (render the HTML directly).
4. On render-complete: obtain `PrintDocumentAdapter` and hand it to `SilentPdfPrinter`.
5. Emit `ConversionStage` events throughout.
6. Tear down WebView + temp state, return the PDF path.

Lifecycle care: the WebView **must** be retained until the print job finishes (framework calls its callbacks asynchronously); destroy only after `onWriteFinished`.

### 3.2 Offscreen WebView + `WebViewAssetLoader`

- Created programmatically (not attached to the view tree) with JavaScript enabled.
- `androidx.webkit.WebViewAssetLoader` maps `https://appassets.androidplatform.net/word/…` → `assets/word/`.
- Using a real `https` origin (not `file://`) keeps the same-origin policy intact so `fetch()` of the document works — the same pattern used by Android's own docs and by production offline viewers.

### 3.3 `index.html` (render host)

Structure:

```html
<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <style>
    /* 1. Force zero page margin; margins come from docx <section> padding */
    @media print { @page { margin: 0; } }

    /* 2. Metric-compatible font twins (registered under WORD names) */
    @font-face { font-family:"Calibri"; src:url("Carlito-Regular.ttf"); }
    @font-face { font-family:"Cambria"; src:url("Caladea-Regular.ttf"); }
    @font-face { font-family:"Times New Roman"; src:url("LiberationSerif-Regular.ttf"); }
    @font-face { font-family:"Arial"; src:url("LiberationSans-Regular.ttf"); }
    @font-face { font-family:"Courier New"; src:url("LiberationMono-Regular.ttf"); }

    /* 3. Kill wrapper chrome so only page boxes print */
    @media print { .docx-wrapper { background: #fff !important; padding: 0 !important; } }
  </style>
</head>
<body>
  <div id="doc"></div>
  <script src="jszip.min.js"></script>
  <script src="docx-preview.umd.js"></script>
  <script src="bridge.js"></script>
</body>
</html>
```

`bridge.js` responsibilities:

```js
async function renderFromUrl(url) {
  try {
    AndroidBridge.onProgress("parsing", 10);
    const buf = await (await fetch(url)).arrayBuffer();
    await docx.renderAsync(buf, document.getElementById("doc"), null, {
      breakPages: true,
      renderHeaders: true,
      renderFooters: true,
      renderFootnotes: true,
      renderEndnotes: true,
      ignoreLastRenderedPageBreak: false,
      useBase64URL: true,
      inWrapper: true,
    });
    await document.fonts.ready;                 // CRITICAL: settle fonts before print
    AndroidBridge.onProgress("paginating", 90);
    const pages = document.querySelectorAll(
      ".docx-wrapper > section.docx").length;
    AndroidBridge.onRendered(pages);
  } catch (e) {
    AndroidBridge.onError(String(e && e.message || e));
  }
}
```

Design notes:
- `ignoreLastRenderedPageBreak:false` → honor the break positions Word last computed (important for long tables and CJK docs).
- `useBase64URL:true` → images/fonts inlined so nothing is fetched at print time.
- `document.fonts.ready` is a hard gate; printing before fonts settle yields wrong line breaks.

### 3.4 Legacy `.doc` path (Apache POI HWPF)

```
OLE2 bytes ──► HWPFDocument ──► WordToHtmlConverter (or manual Range/Table walk) ──► styled HTML
```

- `HWPFDocument` from `poi-scratchpad`; POIFS from `poi` core.
- **JAXP risk:** `WordToHtmlConverter` uses `javax.xml.transform`. Android ships a JAXP impl, but this is the classic POI-on-Android pain point → validate in Phase 0.
- **`javax.imageio` risk:** HWPF picture extraction references `javax.imageio` (absent on Android). Guard the image branch; images in `.doc` are best-effort.
- **log4j:** ship no-op stub classes under `org.apache.logging.log4j.*` so POI does not `NoClassDefFoundError`.
- Output HTML is rendered through the **same** WebView, so it inherits the identical print path and fidelity behavior.

### 3.5 `android.print.SilentPdfPrinter.kt`

**The problem:** `PrintDocumentAdapter.LayoutResultCallback` and `WriteResultCallback` have **package-private constructors** in the Android SDK. A subclass declared outside `android.print` cannot invoke `super()`, so you cannot instantiate the callbacks — which is why most code resorts to DexMaker/reflection.

**The solution:** declare our own source file inside the `android.print` package. At runtime it shares the package namespace with the bootclasspath `android.print` classes and therefore has access to the package-private constructors — **no hidden-API reflection, no DexMaker.**

```kotlin
// android/app/src/main/kotlin/android/print/SilentPdfPrinter.kt
package android.print

import android.os.CancellationSignal
import android.os.ParcelFileDescriptor
import java.io.File

/**
 * Drives a PrintDocumentAdapter's lifecycle to emit a PDF file
 * without showing the system print dialog.
 *
 * Placed in package android.print on purpose: LayoutResultCallback and
 * WriteResultCallback have package-private constructors, so only a class
 * in this package may instantiate them.
 */
class SilentPdfPrinter(private val attributes: PrintAttributes) {

    fun print(
        adapter: PrintDocumentAdapter,
        onProgress: (Int) -> Unit,
        onDone: (File) -> Unit,
        onError: (String) -> Unit,
    ) {
        adapter.onLayout(
            null, attributes, CancellationSignal(),
            object : PrintDocumentAdapter.LayoutResultCallback() {
                override fun onLayoutFinished(info: PrintDocumentInfo, changed: Boolean) {
                    onProgress(50)
                    val file = File.createTempFile("doc2pdf-", ".pdf") // caller supplies dir
                    val pfd = ParcelFileDescriptor.open(
                        file, ParcelFileDescriptor.MODE_READ_WRITE)
                    adapter.onWrite(
                        arrayOf(PageRange.ALL_PAGES), pfd, CancellationSignal(),
                        object : PrintDocumentAdapter.WriteResultCallback() {
                            override fun onWriteFinished(pages: Array<PageRange>) {
                                pfd.close(); onProgress(100); onDone(file)
                            }
                            override fun onWriteFailed(error: CharSequence?) {
                                pfd.close(); onError(error?.toString() ?: "write failed")
                            }
                        })
                }
                override fun onLayoutFailed(error: CharSequence?) {
                    onError(error?.toString() ?: "layout failed")
                }
            })
    }
}
```

`PrintAttributes`:
```
MediaSize  = A4 (or first section's size; UNKNOWN_PORTRAIT fallback)
Resolution = 600 × 600 dpi
ColorMode  = COLOR (or MONO)
Margins    = NO_MARGINS   // docx <section> padding owns margins
```

---

## 4. Data Flow — `.docx` (happy path)

```text
1  Dart: FilePicker → path
2  Dart → Kotlin  convertToPdf{sourcePath}
3  Kotlin: sniff → "docx"
4  Kotlin: create WebView, load assets/word/index.html
5  Kotlin → JS: renderFromUrl("https://appassets.../doc.bin")
6  JS: fetch → docx.renderAsync → await fonts.ready → onRendered(pages)
7  Kotlin: createPrintDocumentAdapter → SilentPdfPrinter.print
8  Framework: onLayoutFinished → onWrite → PDF written to a cache working copy
9  Kotlin: publish a copy into shared Documents/doc2pdf (MediaStore on API 29+),
   then → Dart: { outputPath, savedLocation, savedName, pageCount, format, durationMs }
10 Dart: result_screen(pdfrx preview of the working copy) → Save / Share
```

Progress events fire between steps 3–9. Cancellation is cooperative: a `cancel` call flips a flag checked between phases and destroys the WebView.

---

## 5. Data Flow — legacy `.doc`

Identical after step 3, except step 5 becomes:

```text
Kotlin: HWPFDocument → HTML string → webView.loadDataWithBaseURL(html)
        → onRendered → same print path
```

The result carries `sourceFormat:"doc"`, and the UI shows the *basic formatting* banner.

---

## 6. Threading Model

| Work | Thread |
|---|---|
| MethodChannel handler | main thread (required for WebView creation) |
| WebView render | WebView's internal renderer thread |
| POI parse | background executor (never main) |
| Print callbacks | framework threads |
| Result copy/save | background executor (`ExecutorService`) |

Rule: **WebView must be created and driven on the main thread**; heavy parsing must not block it.

---

## 7. Error Taxonomy

| Code | Cause | UI response |
|---|---|---|
| `unsupported_format` | not docx/doc | inline error on converter screen |
| `doc_encrypted` | password-protected | password sheet (docx-preview `decryptDocx`) |
| `doc_unreadable` | corrupt / pre-97 binary | error card with retry |
| `render_failed` | JS exception | error card, "report" affordance |
| `print_failed` | adapter failure | error card + retry |
| `cancelled` | user cancel | silent return to converter |

---

## 8. Security & Privacy

- `INTERNET` / `ACCESS_NETWORK_STATE` exist **only** for the AdMob SDK; the render WebView is offline and conversion works in airplane mode.
- No ad SDK access to document bytes; the app keeps no analytics or telemetry of its own.
- Render WebView CSP: `connect-src 'none'`; navigation outside the asset origin refused.
- Document bytes live only in a short-lived app-private `cacheDir` working copy (wiped before each conversion); the PDF is also published to shared storage because that is the artifact the user keeps.
- No analytics, no telemetry, no ads (v1).
- Shared-storage writes go through `MediaStore` on Android 10+ (`Documents/doc2pdf`); API 26-28 writes the same folder through `WRITE_EXTERNAL_STORAGE` (`maxSdkVersion="28"`). Raw paths are never used on 10+.

---

## 9. Testing Strategy

| Level | What | How |
|---|---|---|
| Unit (Dart) | channel wrapper, models, providers | `flutter_test` + fake channels |
| Unit (Kotlin) | header sniffing, path routing | JUnit |
| Integration | full convert on real files | instrumented test + fixtures |
| **Fidelity (dev)** | SSIM vs Word | Node harness (plan.md §Phase 2) |
| Manual | per-OEM print quirks | device matrix |

---

## 10. Why These Choices (decision log)

| Decision | Rationale | Rejected alternative |
|---|---|---|
| docx-preview (JS) over mammoth | preserves layout/geometry | mammoth = semantic-only |
| Native WebView over `flutter_inappwebview` | keeps render+print in one place; fewer deps | — |
| Silent `PrintDocumentAdapter` over `Printing.convertHtml` | no dialog, vector, not deprecated | printing (flaky, Android 13+ broken) |
| `poi` + `poi-scratchpad` only | HWPF needs no OOXML/XMLBeans; −14 MB, avoids conflicts | full POI stack |
| `pdfrx` over `pdfx` | maintained; consistent with sibling apps | pdfx |
| `package android.print` bridge | avoids hidden-API reflection for package-private ctors | DexMaker |
| Metric-compatible fonts | Word-matching pagination without licensing | ship MS fonts (illegal) |
| `MediaStore` for shared output | scoped-storage correct on Android 10+; `Documents/doc2pdf` is visible to every app | app-private documents dir (invisible to users); `MANAGE_EXTERNAL_STORAGE` (hostile prompt) |
| Cache working copy + shared publish | Preview/Share need a readable path; the public copy is the user's artifact | sharing `content://` (share_plus sends it as text); duplicate permanent copy |
| Media print resolution set explicitly | WebView's adapter throws `attributes must specify print resolution` without it | relying on framework defaults |
| AdMob behind a best-effort `AdService` | conversion must never depend on the network; every ad path swallows failure and can be disabled with `AdConfig.enabled` | calling `MobileAds` directly from widgets |
| Banner on the scaffold, not in bodies | one instance survives picker/result/progress swaps, and stays clear of Convert/Preview/Share | per-screen banner widgets (reload churn, click risk) |
