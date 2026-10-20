# doc2pdf — Product Requirements Document (PRD)

**App:** Word → PDF converter, Android, on-device conversion.
**Status:** v2 — supersedes the original `mammoth.js` approach.

> See also: [`plan.md`](./plan.md) · [`architecture.md`](./architecture.md) · [`design.md`](./design.md)

---

## 1. Overview

`doc2pdf` converts Microsoft Word documents (`.docx`, `.doc`) to PDF **entirely on-device**, with no accounts and no print dialog. The document never leaves the phone. The app is ad-supported: the AdMob SDK is the only component that talks to the network, and it never sees the files being converted.

- `.docx` targets **~0.9 SSIM** fidelity vs Microsoft Word (layout-faithful).
- `.doc` (Word 97-2003) is supported at a clearly-labeled **basic** fidelity tier.

---

## 2. Goals

| Goal | Metric |
|---|---|
| Offline conversion | Conversion works in airplane mode (ads simply do not load) |
| High fidelity (`.docx`) | ~0.9 SSIM vs Word on a fixture corpus |
| Fast | Typical document converts in seconds |
| Private | Zero uploads, zero telemetry; `INTERNET` used only by AdMob |
| Monetized | Anchored adaptive banner + capped interstitial, sample IDs until release |
| Clear UX | User always knows the stage and the output quality |

**Non-goals (v1):** iOS/desktop/web, `.rtf`/`.odt`, editing, OCR, batch conversion, cloud conversion.

---

## 3. Core Strategy

```text
docx-preview (bundled JS) in an offscreen WebView
        │  layout-faithful, paginated HTML with real page geometry
        ▼
android.webkit.WebView.createPrintDocumentAdapter()
        │  driven silently via a package android.print bridge
        ▼
PdfDocument  →  vector, selectable PDF  →  saved / shared
```

**Why not `mammoth.js` + `Printing.convertHtml` (the original plan):**

- `mammoth.js` is *semantic-only* — it intentionally drops fonts, colors, sizes, and page layout. It is the wrong tool for a visual converter.
- `Printing.convertHtml()` is deprecated, inconsistent across OEM WebViews, broken on Android 13+, and `MissingPluginException` on desktop.
- `docx-preview` preserves page geometry, headers/footers, tables, numbering, fonts, and honors Word's saved page breaks. Android's print framework then emits a vector PDF **without any user-facing dialog**.

---

## 4. Supported Formats

| Format | Tier | Engine | Fidelity |
|---|---|---|---|
| `.docx` | Full | docx-preview (JS) | ~0.9 SSIM vs Word |
| `.doc` (97-2003) | Basic | Apache POI HWPF | text, tables, character formatting; images best-effort |
| `.docx` (encrypted) | Full | docx-preview `decryptDocx` | prompts for password |

---

## 5. Technical Requirements

### 5.1 Packages

**Flutter (`pubspec.yaml`)**
```yaml
dependencies:
  file_picker: ^8
  pdfrx: ^1              # offline PDF preview
  path_provider: ^2
  share_plus: ^10
  flutter_riverpod: ^2
```
> `flutter_inappwebview` and `printing` are **not** used — the render WebView is created natively in Kotlin.

**Android (`app/build.gradle.kts`)**
```kotlin
implementation("androidx.webkit:webkit:1.12.1")        // WebViewAssetLoader
implementation("org.apache.poi:poi:5.2.5")             // POIFS core
implementation("org.apache.poi:poi-scratchpad:5.2.5")  // HWPF for legacy .doc
```
> `poi-ooxml` and `xmlbeans` are **removed** — docx-preview handles `.docx`. Saves ~14 MB and avoids StAX/XMLBeans Android conflicts.

**Bundled assets** — `android/app/src/main/assets/word/`: `index.html`, `docx-preview.umd.js`, `jszip.min.js`, and metric-compatible fonts (Carlito, Caladea, Liberation Sans/Serif/Mono — SIL OFL).

### 5.2 Fidelity Levers (mandatory)

1. Bundle metric-compatible fonts (Calibri→Carlito, Cambria→Caladea, Arial→Liberation Sans, Times→Liberation Serif, Courier→Liberation Mono).
2. docx-preview: `useBase64URL:true`, `ignoreLastRenderedPageBreak:false`, headers/footers/footnotes on.
3. `document.fonts.ready` before printing.
4. `@media print { @page { margin: 0 } }` + `PrintAttributes.Margins.NO_MARGINS` so page padding = Word margins.

### 5.3 Privacy & Security

- `INTERNET` / `ACCESS_NETWORK_STATE` are declared **only** for the AdMob SDK; conversion itself never touches the network and the render WebView stays offline.
- Render WebView CSP `connect-src 'none'`.
- Document bytes live only in a short-lived app-private cache working copy (preview + share); the finished PDF is published to shared `Documents/doc2pdf`.
- Published via `MediaStore` (scoped storage) on Android 10+; on Android 8/9 the same folder is written through `WRITE_EXTERNAL_STORAGE` (`maxSdkVersion="28"`), prompting once.
- No ad SDK access to document contents; no analytics or telemetry beyond what AdMob itself performs.

### 5.4 Ads

| Item | Decision |
|---|---|
| SDK | `google_mobile_ads` (AdMob), UMP/GDPR consent gate before the first load |
| Banner | Anchored adaptive, mounted on the home scaffold's `bottomNavigationBar` — visible across picker, result and progress states, never adjacent to Convert/Preview/Share |
| Interstitial | One per successful conversion, capped at one show per 3 minutes |
| Failure mode | Ads are best-effort: with no network or a failed load the app behaves exactly as before |
| Inventory | Google sample IDs until the AdMob app/units for `com.magnatrus.doc2pdf` are created, then swapped in `AdConfig` + the manifest |

---

## 6. Color Combination

Design system (full spec in [`design.md`](./design.md)). Every token has a light and dark value.

### 6.1 Brand

| Token | Light | Dark | Use |
|---|---|---|---|
| Primary | `#4F46E5` | `#A5B4FC` | brand, primary actions |
| On-primary | `#FFFFFF` | `#1E1B4B` | text on primary |
| Primary container | `#E0E7FF` | `#312E81` | chips, dropzone tint |
| On-primary container | `#1E1B4B` | `#E0E7FF` | content on container |

### 6.2 Semantic

| Token | Light | Dark | Meaning |
|---|---|---|---|
| Success | `#16A34A` | `#4ADE80` | done / saved |
| Success container | `#DCFCE7` | `#14532D` | success surface |
| Warning | `#B45309` | `#FBBF24` | `.doc` basic notice |
| Warning container | `#FEF3C7` | `#78350F` | warning surface |
| Error | `#DC2626` | `#F87171` | failures |
| Error container | `#FEE2E2` | `#7F1D1D` | error surface |
| Info | `#0284C7` | `#38BDF8` | tips |
| Info container | `#E0F2FE` | `#0C4A6E` | info surface |

### 6.3 Neutral / Surface

| Token | Light | Dark | Use |
|---|---|---|---|
| Background | `#F8FAFC` | `#0B0E14` | app background |
| Surface | `#FFFFFF` | `#12151C` | cards, sheets |
| Surface variant | `#F1F5F9` | `#1B1F27` | inputs, rows |
| Outline | `#E2E8F0` | `#2A2F3A` | borders |
| On-surface | `#0F172A` | `#E6E9EF` | primary text |
| On-surface variant | `#475569` | `#9AA3B2` | secondary text |

### 6.4 Document / Viewer

| Token | Light | Dark | Rule |
|---|---|---|---|
| PDF page | `#FFFFFF` | `#FFFFFF` | **never invert content** |
| Viewer backdrop | `#E2E8F0` | `#0B0E14` | behind the page |

**Summary:** an **indigo + slate** palette — primary `#4F46E5`, neutral slate surfaces, semantic green/amber/red/blue accents. In dark mode indigo lightens to `#A5B4FC`, surfaces go near-black (`#0B0E14` / `#12151C`), and PDF pages stay pure white.

---

## 7. UX Flow

1. **Home** — dropzone card (*"Tap to select a Word document"*), format badges, recent conversions, privacy footer.
2. **Processing** — staged progress (Sniffing → Parsing → Rendering → Paginating → Printing) with a document skeleton and cancel.
3. **Result** — `pdfrx` preview, file-size/count/format badge, **Saved to `Documents/doc2pdf`** line, **Save to Device** + **Share PDF**.
4. Encrypted `.docx` → password sheet. Legacy `.doc` → persistent *basic formatting* banner.
5. Full **light & dark** themes (System / Light / Dark), following the system by default.

Detailed screens, components, and dark-mode rules: [`design.md`](./design.md).

---

## 8. Acceptance Criteria

- [ ] `.docx` → vector PDF, correct page count / headers / tables, **no dialog**, offline.
- [ ] `.doc` → basic PDF with a clear banner.
- [ ] Encrypted `.docx` handled with a password prompt.
- [ ] SSIM harness green on the fixture corpus.
- [ ] Full flow: pick → convert → preview → save (MediaStore) → share.
- [ ] Light and dark themes complete and contrast-checked (AA).
- [ ] `INTERNET` present only for AdMob; conversion works in airplane mode with no ads shown.
