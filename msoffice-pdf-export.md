# doc2pdf — How Microsoft Office Converts DOC/DOCX to PDF

Companion research note to [`architecture.md`](./architecture.md), [`plan.md`](./plan.md), and [`design.md`](./design.md).

This document records how Microsoft Office itself turns a Word document into a PDF, so that doc2pdf's fidelity decisions are grounded in the real mechanism rather than guesswork.

---

## 1. Purpose & Scope

**Question:** how does Microsoft Word actually produce a PDF from a `.doc`/`.docx`?

**Why it matters for doc2pdf:** Word's output is the fidelity reference we target (~0.9 SSIM for `.docx`). Understanding where its text/vector/selectability come from tells us which losses are inherent to our pipeline and which are bugs to fix.

**Scope:** Word (and the Office suite generally) on Windows and macOS, covering Office 2007 through Microsoft 365. Not covered here: Excel/PowerPoint specifics beyond shared architecture, or third-party export stacks except as contrast.

---

## 2. Two Entirely Separate Conversion Paths

Word reaches PDF by two different code paths. They are **not** the same engine and can produce different output.

| Path | Trigger | Mechanism |
|---|---|---|
| **Save As / Export → PDF** | File menu, `Document.ExportAsFixedFormat` | Office's **own built-in fixed-format exporter**. No printer driver involved. |
| **Print → Microsoft Print to PDF** | Print dialog, "Microsoft Print to PDF" | Normal **Windows print pipeline**: GDI → EMF spool → print processor → PDF driver. Driver-dependent. |

- The built-in exporter has shipped with Word since **Office 2007 Service Pack 2 (April 2009)**. Before SP2 it was a separately downloadable add-in (the renderer lived in `EXP_PDF.DLL`); it was withheld from RTM because of legal objections from Adobe, then restored natively in SP2.
- Because the print path routes through a Windows printer driver, its fidelity and its text/vector behavior can vary with the selected driver, whereas the built-in exporter is fixed.

---

## 3. The Core Mechanism: Layout → EMF → PDF

Office does not rasterize pages to reach PDF (unless forced). The sequence is:

1. **Word lays out and paginates** the document using its own layout engine.
2. **Each page is rendered to an in-memory EMF** — an Enhanced Metafile, i.e. a sequence of GDI/GDI+ drawing commands ("draw text here", "draw a line there", "draw this image").
3. Office calls the exporter **once per page** via `IMsoDocExporter::HrAddPageFromEmf(HENHMETAFILE hemf)`. Microsoft's documentation states the EMF is *"the primary source of the content that the add-in exports as a fixed-format file."*
4. **The exporter translates EMF records into PDF content** (vector path operators, image XObjects, text objects).

The critical consequence: because pages cross the boundary as **EMF drawing records**, text stays text and graphics stay vector during the hand-off. That is the structural reason Word PDFs are resolution-independent with selectable text.

---

## 4. Why Text Stays Vector and Selectable

Within the per-page EMF, text is carried by real drawing records, not pixels:

| EMF record | Role |
|---|---|
| `EMR_EXTTEXTOUTW` / `EMR_EXTTEXTOUTA` | Draws Unicode / ANSI text runs using the current font, color, and transform. |
| `EMR_EXTCREATEFONTINDIRECTW` | Creates the logical font (face name, height, weight, italic, charset) used by text records. |

A plain EMF renderer that omits these records loses all embedded text — which is exactly the class of bug doc2pdf hit with the letterhead `image1.emf` (see §10).

**Glyphs vs. source characters:** some text records draw *glyphs* (indices into a font) rather than original Unicode code points. Glyph→character mapping is context-dependent (ligatures combine code points; a code point can split across glyphs), so a glyph-only document is not reliably searchable. Office therefore injects companion Unicode:

- `DocExComment_BeginTextRun` / `DocExComment_EndTextRun` — carry the Unicode actual-text and a glyph-index table for a bounded run.
- `DocExComment_UnicodeForNextTextOut` — carries the Unicode for only the *next* text-out record.

A PDF consumer uses this to make the output searchable/copyable even when the drawing records carried glyphs.

---

## 5. Semantic Information Rides Along as EMF Comment Records

Conventional EMF can express drawing but has no notion of hyperlinks, reading order, locale, or accessibility. Office injects semantic data into the EMF as **special-formatted comment records** (`EMR_COMMENT` with a private signature). A normal GDI renderer ignores them; the exporter interprets them.

| Comment record | Semantics carried |
|---|---|
| `DocExComment_ExternalHyperlink(Rctfv)` | Out-of-document link target + clickable region. |
| `DocExComment_InternalHyperlink(Rctfv)` | In-document link target (page + point). |
| `DocExComment_BeginTextRun` / `EndTextRun` | Unicode + glyph map for a text run. |
| `DocExComment_UnicodeForNextTextOut` | Unicode for the next text record. |
| `DocExComment_BeginStructNode` / `EndStructNode` | Document structure tree: article, paragraph, heading, table, list, figure, textbox, header/footer, etc. Drives reading order and tagging. |
| `DocExComment_ColorInfo` / `ColorEnable` | Color-state mapping for extended color support. |
| `DocExComment_EPSColor` / `EPSColorCMYKJPEG` / `EPSColorSpotImage` | EPS/CMYK/spot-color info. |
| `DocExComment_PageName` | Page name. |
| `DocExComment_Transparent` | Transparency marker. |
| `DocExComment_BoundingBox` | Bounding box (recent versions). |

By reconstructing these, the exporter produces **hyperlinks, bookmarks, tagged/accessible PDF, and PDF/UA** metadata. Structure nodes can span multiple pages; those that fit on a page are embedded in the EMF, and multi-page nodes are passed via `HrBeginStructNode`/`HrEndStructNode` so the tree remains consistent across the per-page EMFs.

---

## 6. EMF vs. EMF+

**EMF+** is the GDI+ descendant of WMF/EMF. It is semantically a separate format whose records are **embedded inside EMF comment records** (`EMR_COMMENT_EMFPLUS`). It exists because plain EMF lacks key capabilities:

| Capability | Plain EMF | EMF+ |
|---|---|---|
| Transparency / alpha (ARGB) | Limited (via `EMR_ALPHABLEND`) | Yes, native ARGB |
| Gradients (linear/path) | `EMR_GRADIENTFILL` | `EmfPlusLinearGradientBrushData`, path gradients |
| Custom line caps, texture brushes | Partial | Yes |

Two EMF+ layouts exist:

- **EMF+ Only** — EMF+ records do the drawing; systems without EMF+ playback cannot render it correctly.
- **EMF+ Dual** — a complete plain-EMF drawing is also present, so non-EMF+ players render a fallback. Players pick one or the other; they are not blended.

---

## 7. Fonts and Output Options

Word's `ExportAsFixedFormat` family exposes the fidelity knobs. `ExportAsFixedFormat3` is the current full form (earlier `ExportAsFixedFormat` / `2` are subsets).

| Parameter | Effect |
|---|---|
| `ExportFormat` | PDF or XPS. |
| `OptimizeFor` | Optimize for **print** vs **screen**. |
| `Range` / `From` / `To` | Whole document, current page, or a page range. |
| `Item` | Text only vs text with markup. |
| `IncludeDocProps` | Include document properties. |
| `KeepIRM` | Copy IRM/sensitivity labels + encryption to output. |
| `CreateBookmarks` | Export bookmarks / bookmark type. |
| `DocStructureTags` | Emit structure tags for screen readers (tagged PDF). Default `true`. |
| `BitmapMissingFonts` | If a font license forbids embedding, include a **bitmap of the text** instead. Default `true`. |
| `UseISO19005_1` | Restrict output to **PDF/A-1 (ISO 19005-1)**. |
| `OptimizeForImageQuality` | Keep original image quality (larger) vs downsample. |
| `ImproveExportTagging` | Improved accessibility tagging (footnotes/endnotes, block quotes, captions, title, comments, equations, layout tables, nodes spanning pages). |
| `FixedFormatExtClassPtr` | Pointer to an add-in implementing an alternate exporter. |

**Font embedding:** fonts are **subsetted and embedded by default** to keep files small. `BitmapMissingFonts=true` (the default) rasterizes text only when a license forbids embedding; setting it `false` references the font and relies on viewer substitution. `UseISO19005_1` maps to PDF/A, and `DocStructureTags` to tagged PDF.

---

## 8. Extensibility (Office 2024+)

Since Office 2024 / LTSC 2024 / Microsoft 365 v2408, third parties can supply their own exporter for the fixed-format pipeline:

- Implement the COM interface **`IMsoDocExporter`**, pass it to `ExportAsFixedFormat` via `FixedFormatExtClassPtr`.
- Office drives it through callbacks including `HrCreateDoc`, `HrAddPageFromEmf` (per page), metadata/outline methods, `HrBeginStructNode`/`HrEndStructNode`, pagination methods, and `HrFinalize`.
- `IMsoDocExporterSite` provides extended color support (e.g. `SetEPSInfo`).

This is the officially documented, supported extension point — and it confirms that **the per-page EMF is the contract** between Office and *any* PDF/XPS exporter.

---

## 9. Platform Contrast: Windows, macOS, LibreOffice

| Platform | PDF generation path |
|---|---|
| **Word for Windows (Save As/Export)** | Office layout → per-page EMF → built-in EMF→PDF exporter (or a `FixedFormatExtClassPtr` add-in). |
| **Word for Windows (Print to PDF)** | GDI → EMF spool file → Windows print processor → "Microsoft Print to PDF" driver. |
| **Word for Mac** | **Apple Quartz / CoreGraphics** PDF graphics context — a native, resolution-independent PDF generator. Not the Windows EMF path, which is why Mac export behavior differs (e.g. the trade-off between preserving vector graphics and preserving hyperlinks depending on export option). |
| **LibreOffice (reference only)** | Each printed page is recorded into a `GDIMetaFile`, then converted by `vcl::PDFWriter`. Embedded EMF+ is parsed/rendered in `cppcanvas`. |

---

## 10. Implications for doc2pdf

doc2pdf's pipeline is architecturally different from Word's:

```
DOCX ──► docx-preview (layout-faithful HTML/CSS) ──► WebView.createPrintDocumentAdapter()
                                                       ──► android.print ----► vector PDF
```

We **never produce EMF**. Our natively generated content (text, rules, images we draw/place ourselves) is emitted as vector PDF by Android's print backend, so it stays selectable and resolution-independent.

The one place this bites is **embedded metafiles**. A DOCX can contain an EMF/WMF image (e.g. a letterhead), and *that image's* text lives inside EMF text records (`EMR_EXTTEXTOUTW` / `EMR_EXTCREATEFONTINDIRECTW`). A generic JS EMF renderer that does not implement those records silently drops the text:

- Observed: Doc A's letterhead carried "Engr. Dr. Yusuf Ibrahim" and "BEng (Electrical), MSc (Computer), PhD (Computer)" as EMF text records inside `image1.emf`; the initial renderer drew nothing for them.
- Fix: doc2pdf now parses the EMF text/font records (`parseEmfTextRuns`, `readLogFontFaceName`, `colorRefToHex`) and overlays real HTML text over the EMF bitmap in `docx-preview.js`, preserving selectability.

Net: Word treats embedded-EMF text as first-class because EMF *is* its page transport; we had to add an explicit recovery layer because it is not ours.

---

## 11. References

- `Document.ExportAsFixedFormat3` (Word): https://learn.microsoft.com/en-us/office/vba/api/word.document.exportasfixedformat3
- `Document.ExportAsFixedFormat2` (Word): https://learn.microsoft.com/en-us/office/vba/api/word.range.exportasfixedformat2
- Extending Office PDF Export (`IMsoDocExporter`, `HrAddPageFromEmf`, `DocExComment_*`): https://learn.microsoft.com/en-us/office/pdf/extendingofficepdfexport
- Extend the fixed-format export feature in Word Automation Services: https://learn.microsoft.com/en-us/sharepoint/dev/general-development/extend-the-fixed-format-export-feature-in-word-automation-services
- `[MS-EMF]` — `EMR_EXTTEXTOUTW`: https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-emf/a59a79ac-328e-492d-a34d-e02727af6edf
- `[MS-EMF]` — `EMR_GRADIENTFILL`: https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-emf/1a3849c8-be6c-4d30-b5d3-f43b4c70ca0d
- `[MS-EMFPLUS]` — Metafile Structure (EMF+ embedded in EMF comment records): https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-emfplus/8b9363ba-cf5b-4d35-bced-0620e3b5b5ef
- `[MS-EMFPLUS]` — Structure Object Types (ARGB, gradients, pens): https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-emfplus/b1e477d3-ea42-43c1-9fd3-d49c5b922372
- Save As PDF vs Print to PDF (Microsoft Q&A): https://learn.microsoft.com/en-us/answers/a/11789163
- Word for Mac export fidelity / Quartz (Microsoft Q&A): https://learn.microsoft.com/en-us/answers/questions/5082072/problems-exporting-a-word-file-to-pdf-on-mac-with
- Word for Mac vector/hyperlink trade-off: https://learn.microsoft.com/en-us/answers/questions/5239934/print-pdf-macos-vs-windows-the-challenge-between-g
- Office 2007 SP2 built-in Save As PDF/XPS: https://learn.microsoft.com/en-us/archive/blogs/erikaehrli/office-2007-service-pack-2-download-and-improvements-for-developers
- Office 2007 PDF history: https://en.wikipedia.org/wiki/Microsoft_Office_2007
- Windows printer driver architecture (EMF spool, XPSDrv): https://learn.microsoft.com/en-us/windows-hardware/drivers/print/printer-driver-architecture
- Quartz 2D / CoreGraphics PDF contexts: https://developer.apple.com/library/archive/documentation/GraphicsImaging/Conceptual/drawingwithquartz2d/dq_overview/dq_overview.html
- LibreOffice VCL print/PDF export: https://docs.libreoffice.org/vcl.html
- Aspose — MS Word uses embedded EMF in WMF: https://reference.aspose.com/words/net/aspose.words.saving/metafilerenderingoptions/useemfembeddedtowmf/
