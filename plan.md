# doc2pdf — Implementation Plan

**Word → PDF converter for Android.**
Target: `.docx` at ~0.9 SSIM vs Microsoft Word, legacy `.doc` at a clearly-labeled *basic* tier. Conversion is fully on-device, with no print dialog.

---

## 1. Goal & Accepted Constraints

| Item | Decision |
|---|---|
| Platform | **Android only** |
| Network | Conversion requires no network; `INTERNET` is declared for AdMob only |
| `.docx` fidelity | ~0.9 SSIM vs Word (layout-faithful) |
| `.doc` fidelity | **Basic** tier (Apache POI HWPF) — text, tables, character formatting; images best-effort |
| Inputs | `.docx`, `.doc` |
| Output | Vector, selectable PDF saved to device + shareable |
| Scope | Full app: engine + UI/UX |

**Non-goals (v1):** iOS/desktop/web, `.rtf`/`.odt`, editing, OCR, batch, cloud conversion.

---

## 2. Core Strategy

Replace the original PRD's `mammoth.js` + `Printing.convertHtml` path with a **native render + silent print pipeline**:

```
docx-preview (bundled JS) in an offscreen WebView
        │  (layout-faithful, paginated HTML + real page geometry)
        ▼
android.webkit.WebView.createPrintDocumentAdapter()
        │  (driven silently via package android.print bridge)
        ▼
PdfDocument  →  vector, selectable PDF
```

**Why this wins over the PRD:**

- `mammoth.js` is *semantic-only* — it deliberately drops fonts, colors, sizes, and layout. Wrong tool for a visual converter.
- `Printing.convertHtml()` is deprecated, inconsistent across OEM WebViews, broken on Android 13+, and throws `MissingPluginException` on desktop.
- `docx-preview` preserves page geometry, headers/footers, tables, numbering, fonts, and honors Word's saved page breaks.
- Driving the `PrintDocumentAdapter` lifecycle directly produces a PDF **with no user-facing print dialog**, in vector form.

---

## 3. Dependencies

### 3.1 Flutter — `pubspec.yaml`

```yaml
dependencies:
  file_picker: ^8            # pick .docx / .doc
  pdfrx: ^1                  # offline PDF result preview (PDFium)
  path_provider: ^2          # app-private output/cache dirs
  share_plus: ^10            # share sheet
  flutter_riverpod: ^2       # state management

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^6
  # dev-only fidelity harness (see §8) runs via Node, not Dart packages
```

> **Removed from the original PRD:** `flutter_inappwebview` (the offscreen WebView is created natively in Kotlin) and `printing` (its HTML path is the deprecated one).

### 3.2 Android — `android/app/build.gradle.kts`

```kotlin
implementation("androidx.webkit:webkit:1.12.1")      // WebViewAssetLoader
implementation("org.apache.poi:poi:5.2.5")           // POIFS core
implementation("org.apache.poi:poi-scratchpad:5.2.5") // HWPF: legacy .doc
```

> **Removed:** `poi-ooxml` and `xmlbeans`. docx-preview handles `.docx` in JS, so the OOXML/XMLBeans stack is unnecessary and is a known source of StAX/XMLBeans Android conflicts. Saves ~14 MB.

### 3.3 Bundled Assets — `android/app/src/main/assets/word/`

| Asset | Purpose |
|---|---|
| `index.html` | Render host; loads docx-preview + fonts; exposes bridge |
| `docx-preview.umd.js` | DOCX → paginated HTML (Apache-2.0) |
| `jszip.min.js` | Unzips the `.docx` package (MIT) |
| `Carlito-*.ttf` | Metric twin of **Calibri** (SIL OFL) |
| `Caladea-*.ttf` | Metric twin of **Cambria** (SIL OFL) |
| `LiberationSans-*.ttf` | Metric twin of **Arial** (SIL OFL) |
| `LiberationSerif-*.ttf` | Metric twin of **Times New Roman** (SIL OFL) |
| `LiberationMono-*.ttf` | Metric twin of **Courier New** (SIL OFL) |

Fonts are **the #1 fidelity lever**: identical advance widths mean line breaks and pagination land where Word puts them, without shipping proprietary fonts.

---

## 4. Folder Structure

```text
doc2pdf/
├── plan.md
├── architecture.md
├── design.md
├── pubspec.yaml
├── lib/
│   ├── main.dart
│   ├── app.dart                              # MaterialApp + theme wiring
│   ├── core/
│   │   ├── theme/
│   │   │   ├── app_theme.dart                # light + dark ThemeData
│   │   │   ├── app_colors.dart               # color tokens (see design.md)
│   │   │   ├── app_typography.dart
│   │   │   └── app_spacing.dart
│   │   ├── services/
│   │   │   └── render_pdf_channel.dart       # MethodChannel + EventChannel wrapper
│   │   └── models/
│   │       ├── conversion_result.dart
│   │       ├── conversion_stage.dart
│   │       └── source_format.dart            # docx | doc | unknown
│   └── features/
│       └── word_to_pdf/
│           ├── screens/
│           │   ├── converter_screen.dart
│           │   └── result_screen.dart
│           ├── widgets/
│           │   ├── file_dropzone.dart
│           │   ├── conversion_progress.dart
│           │   ├── result_actions.dart
│           │   └── format_badge.dart
│           └── providers/
│               └── word_to_pdf_provider.dart
├── android/app/src/main/
│   ├── assets/word/…                         # §3.3
│   └── kotlin/
│       ├── android/print/SilentPdfPrinter.kt # package android.print (see §6.4)
│       └── <app>/doc2pdf/
│           ├── MainActivity.kt
│           └── RenderPdfPlugin.kt            # WebView render + POI + print orchestration
└── test/
    ├── fixtures/                             # real .docx / .doc inputs (dev)
    └── word_pdf/                             # Word-exported reference PDFs (dev)
```

---

## 5. MethodChannel Contract

### 5.1 Dart → Kotlin — `MethodChannel("doc2pdf/render")`

| Method | Args | Returns | Throws |
|---|---|---|---|
| `convertToPdf` | `{ sourcePath: String, pageSize: "A4"\|"Letter"\|"auto", colorMode: "color"\|"mono" }` | `{ pdfPath: String, pageCount: int, sourceFormat: "docx"\|"doc", durationMs: int }` | `doc_encrypted`, `doc_unreadable`, `render_failed`, `print_failed`, `unsupported_format` |
| `cancel` | `{}` | `{}` | — |

### 5.2 Kotlin → Dart — `EventChannel("doc2pdf/progress")`

Emits `ConversionStage` events:

```
sniffing | parsing | rendering | paginating | printing | finalizing | done | error(message)
```

### 5.3 Kotlin ↔ JS Bridge (`addJavascriptInterface`)

| Direction | Symbol | Meaning |
|---|---|---|
| JS → Kotlin | `AndroidBridge.onRendered(pageCount)` | docx-preview finished + fonts/layout settled |
| JS → Kotlin | `AndroidBridge.onError(message)` | render failure with detail |
| JS → Kotlin | `AndroidBridge.onProgress(phase, pct)` | optional granular progress |

### 5.4 Asset delivery (avoid base64 bridge limits)

Kotlin serves the source file via `WebViewAssetLoader` under
`https://appassets.androidplatform.net/word/…`; JS `fetch()`es it as an `ArrayBuffer`.
Small files (< ~1 MB) may be inlined as base64. This avoids the JS-bridge string ceiling on large documents.

---

## 6. Implementation Phases

### Phase 0 — Engine Spike (riskiest first)

Deliverable: one real `.docx` (images + table + header/footer) converted to a correct, dialog-free, vector PDF.

1. **`RenderPdfPlugin.kt`** — register MethodChannel; sniff header bytes:
   - `.docx` → `50 4B 03 04` (PK zip)
   - `.doc` → `D0 CF 11 E0 A1 B1 1A E1` (OLE2/CFB)
2. **Offscreen `WebView`** + `WebViewAssetLoader` → load `word/index.html`.
3. **`index.html`** — configure docx-preview:
   ```js
   renderAsync(bytes, body, styleContainer, {
     breakPages: true,
     renderHeaders: true, renderFooters: true,
     renderFootnotes: true, renderEndnotes: true,
     ignoreLastRenderedPageBreak: false,   // honor Word's saved breaks
     useBase64URL: true,                    // self-contained for print
     inWrapper: true,
   })
   ```
   Inject `@font-face` for the five metric twins; force
   `@media print { @page { margin: 0; } }` so docx-preview's section padding is the sole margin source.
4. **Silent print** — `webView.createPrintDocumentAdapter(name)` → drive
   `onLayout(...)` then `onWrite(PageRange.ALL_PAGES, ParcelFileDescriptor, …)`
   via `SilentPdfPrinter` (see §6.4 / architecture.md). `PrintAttributes` = A4, 600 dpi, `Margins.NO_MARGINS`.
5. **Spike validations (must pass before Phase 4):**
   - [ ] WebView print **scale**: CSS-px → print passthrough is 1:1; `@page` honored or margins driven by `PrintAttributes`.
   - [ ] **Mixed page sizes** (A4 + landscape section): decide (a) size job to first section, or (b) per-section print passes. Start with (a).
   - [ ] **HWPF/JAXP**: `WordToHtmlConverter` works on Android, or fall back to manual `Range`/`Table` walk.
   - [ ] **javax.imageio**: legacy `.doc` picture branch guarded (stub or manual extraction).
   - [ ] **log4j shims** present (no-op) so POI doesn't `NoClassDefFound`.

### Phase 1 — Fidelity Pass

- Wire all five metric-twin fonts; verify line breaks + page counts vs Word on a fixture set (Calibri/Cambria/Times/Arial/Courier).
- Encrypted `.docx`: use docx-preview `detectOfficeFileKind` / `decryptDocx`; surface a password prompt (see design.md).
- Tune per-OEM `PrintAttributes` (resolution, margins) and WebView scale.

### Phase 2 — Verification Harness (dev-only, not shipped)

- `test/fixtures/` = 15–25 real `.docx`; `test/word_pdf/` = each exported once to PDF by Word.
- Node script rasterizes both at 150 DPI and computes **SSIM + pixel-diff** (`pdftoppm` + `ssim.js`/`pixelmatch`), reporting per-page and mean.
- CI gate: fail below threshold. This is the only way "perfect" is provable.

### Phase 3 — Legacy `.doc` (Basic Tier)

- OLE2 detected → `HWPFDocument` → HTML → **same** WebView/print path.
- Result screen banner: *"Legacy .doc — basic formatting"*.
- Handle `EncryptedDocumentException` → `doc_encrypted`; unreadable → `doc_unreadable`.

### Phase 4 — UI/UX

Implemented exactly to `design.md` (light + dark):

- `converter_screen`: dropzone card, recent files, format chips.
- `conversion_progress`: staged status + skeleton page animation.
- `result_screen`: `pdfrx` preview, file-size badge, format badge, **Save to Device** / **Share PDF**.
- **Save**: the PDF is published automatically into shared `Documents/doc2pdf` — via `MediaStore` on Android 10+ (scoped storage; **not** `path_provider.getDownloadsDirectory()`), via `WRITE_EXTERNAL_STORAGE` on Android 8/9. A cache working copy serves Preview/Share.
- Riverpod `AsyncNotifier`; EventChannel drives progress UI.
- Full **dark mode** (system + manual override) — see design.md.

### Phase 5 — Edge Cases & Hardening

- 0-byte / corrupt zip / non-Word file → clear error states.
- Large files: stream from asset loader; never base64 giant payloads through Dart.
- Rotation, low storage, revoked URI permission, share without storage permission.
- Accessibility: TalkBack labels, focus order, 48dp targets, contrast in both themes.

---

## 7. Fidelity Levers (Do Not Skip)

1. **Bundled metric-compatible fonts** — without them, pagination drifts. Non-negotiable.
2. `useBase64URL: true` — images/fonts self-contained for printing.
3. `ignoreLastRenderedPageBreak: false` — honor Word's saved break positions.
4. `document.fonts.ready` **before** print — otherwise glyphs/pagination are wrong.
5. `@page { margin: 0 }` + `Margins.NO_MARGINS` — docx section padding = Word margins only.

---

## 8. Risks & Mitigations

| Risk | Severity | Mitigation |
|---|---|---|
| `.doc` fidelity inherently limited | Medium | Label as *basic*; text/tables/formatting only |
| WebView print ignores `@page size` | High | Drive size/margins from `PrintAttributes`; measure scale in Phase 0 |
| Mixed page sizes in one doc | Medium | Size job to first section (v1); per-section passes (v2) |
| HWPF JAXP / `javax.imageio` on Android | High | Spike early; manual range walk / image guards |
| POI needs log4j shims | Medium | Ship no-op `org.apache.logging.log4j` stubs |
| Per-OEM WebView print quirks | Medium | Fallback to `MediaSize.UNKNOWN_PORTRAIT`; test on real devices |
| `androidx.webkit` version drift | Low | Pin version in gradle |

---

## 9. Definition of Done

- [ ] `.docx` → vector PDF, correct page count / headers / tables, **no dialog**, offline.
- [ ] `.doc` → basic PDF with user-facing banner.
- [ ] Encrypted `.docx` handled gracefully.
- [ ] SSIM harness green on the corpus.
- [ ] Full flow: pick → convert (progress) → preview (`pdfrx`) → save (MediaStore) → share.
- [ ] **Light and dark themes** both complete, contrast-checked, and switch on system setting.
- [ ] `INTERNET` declared only for AdMob; the render WebView stays offline.
- [ ] Works with airplane mode on (no ads, conversion unaffected).

---

## 10. Milestones

| # | Milestone | Exit criteria |
|---|---|---|
| M0 | Engine spike | Real `.docx` → correct PDF, no dialog |
| M1 | Fidelity pass | SSIM ≥ target on fixture set |
| M2 | Harness | CI gate active |
| M3 | `.doc` basic | Legacy doc converts with banner |
| M4 | UI/UX | Full flow + dark mode complete |
| M5 | Hardening | Edge cases + accessibility pass |
