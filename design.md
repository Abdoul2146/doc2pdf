# doc2pdf — Design System & UX

Companion to [`plan.md`](./plan.md) and [`architecture.md`](./architecture.md).
**Dark mode is a first-class citizen here, not an afterthought** — every token has a light and a dark value, and the flow is designed for both from the start.

---

## 1. Design Principles

1. **Calm utility.** The app does one thing. The UI gets out of the way; the document is the hero.
2. **Trust in the dark.** Privacy apps are often used at night; the dark theme must be genuinely comfortable, not an inverted afterthought.
3. **Never lie about fidelity.** Format badges and banners state exactly what the output is (`.docx` faithful vs `.doc` basic).
4. **Progress is legible.** Conversion is multi-stage; the user always knows *what* is happening and that they can cancel.
5. **The page is the truth.** PDF content is never color-inverted; only the chrome adapts.

---

## 2. Color

### 2.1 Brand

| Token | Light | Dark | Use |
|---|---|---|---|
| `primary` | `#4F46E5` | `#A5B4FC` | brand, primary actions |
| `onPrimary` | `#FFFFFF` | `#1E1B4B` | text/icons on primary |
| `primaryContainer` | `#E0E7FF` | `#312E81` | chips, dropzone tint, selected |
| `onPrimaryContainer` | `#1E1B4B` | `#E0E7FF` | content on container |

### 2.2 Semantic

| Token | Light | Dark | Meaning |
|---|---|---|---|
| `success` | `#16A34A` | `#4ADE80` | conversion done, saved |
| `successContainer` | `#DCFCE7` | `#14532D` | success surface |
| `warning` | `#B45309` | `#FBBF24` | `.doc` basic-formatting notice |
| `warningContainer` | `#FEF3C7` | `#78350F` | warning surface |
| `error` | `#DC2626` | `#F87171` | failures |
| `errorContainer` | `#FEE2E2` | `#7F1D1D` | error surface |
| `info` | `#0284C7` | `#38BDF8` | tips, neutral callouts |
| `infoContainer` | `#E0F2FE` | `#0C4A6E` | info surface |

### 2.3 Neutral / Surface

| Token | Light | Dark | Use |
|---|---|---|---|
| `background` | `#F8FAFC` | `#0B0E14` | app background |
| `surface` | `#FFFFFF` | `#12151C` | cards, sheets |
| `surfaceVariant` | `#F1F5F9` | `#1B1F27` | inputs, list rows, secondary cards |
| `outline` | `#E2E8F0` | `#2A2F3A` | borders, dividers |
| `outlineStrong` | `#CBD5E1` | `#3A4150` | focused borders |
| `onSurface` | `#0F172A` | `#E6E9EF` | primary text |
| `onSurfaceVariant` | `#475569` | `#9AA3B2` | secondary text, captions |

### 2.4 Document / Viewer (special)

| Token | Light | Dark | Rule |
|---|---|---|---|
| `pageSurface` | `#FFFFFF` | `#FFFFFF` | **PDF page always white** — never invert content |
| `viewerBackdrop` | `#E2E8F0` | `#0B0E14` | area behind the page |
| `pageShadow` | `rgba(15,23,42,0.12)` | `rgba(0,0,0,0.6)` | page elevation |

> **Dark-mode rule:** around a white PDF page, use `viewerBackdrop` (dark) and a strong `pageShadow` so the page reads as paper on a dark desk. Do **not** apply a dark filter to the PDF.

### 2.5 Elevation via surface tint (dark mode)

Material dark elevation is expressed with light overlays, not shadows alone:

| Level | Light | Dark overlay on `surface` |
|---|---|---|
| 0 (background) | `#F8FAFC` | `#0B0E14` |
| 1 (card) | `#FFFFFF` | `surface + primary @ 4%` |
| 2 (raised card) | `#FFFFFF` | `surface + primary @ 6%` |
| 3 (sheet/dialog) | `#FFFFFF` | `surface + primary @ 8%` |

---

## 3. Typography

Font family: **Inter** (bundled) with system fallback. Tabular numerals (`tnum`) for file sizes and page counts.

| Style | Size / Line | Weight | Use |
|---|---|---|---|
| `display` | 32 / 40 | 700 | hero count on result |
| `headline` | 24 / 32 | 700 | screen titles |
| `titleLg` | 20 / 28 | 600 | card titles |
| `title` | 16 / 24 | 600 | list titles, buttons |
| `body` | 14 / 22 | 400 | body text |
| `bodyStrong` | 14 / 22 | 600 | emphasis |
| `label` | 12 / 16 | 600 | chips, badges, overlines |
| `caption` | 12 / 18 | 400 | helper text, file meta |
| `mono` | 13 / 20 | 500 | filenames, sizes |

Letter-spacing: `-0.01em` on ≥20px, `0` below. `label` uses `+0.04em` uppercase.

---

## 4. Spacing, Shape, Motion

**Spacing scale (dp):** `2, 4, 8, 12, 16, 20, 24, 32, 40, 48`. Default screen gutter = **20**.

**Corner radius:** `sm 8` · `md 12` · `lg 16` · `xl 24` · `full 999`.
Cards use `lg` (16), sheets use `xl` top corners (24), buttons/chips use `full`.

**Elevation:** cards `1`, raised `2`, bottom sheets/dialogs `3`.

**Motion:**

| Token | Duration | Curve | Use |
|---|---|---|---|
| `fast` | 150 ms | `easeOut` | ripples, chip select |
| `base` | 250 ms | `easeInOut` | page transitions, expand |
| `slow` | 400 ms | `emphasized` | progress shimmer, sheet |

Respect `MediaQuery.disableAnimations` (reduce motion) → swap shimmer for a static progress bar.

---

## 5. Component Library

### 5.1 Dropzone Card (home hero)

- Large rounded card (`radius lg`), dashed border in `outlineStrong`, background `primaryContainer` at 40% (light) / `surfaceVariant` (dark).
- Center: document-plus icon (48), title *"Tap to select a Word document"*, subtitle *.docx or .doc*.
- Tap → file picker. Pressed → `primary` border + subtle scale `0.99`.
- Dark mode: icon and text use `onPrimaryContainer`; dashed border `outlineStrong`.

### 5.2 Format Badge

Small pill (`radius full`, `label` style):
- `.docx` → `successContainer` / `success` text + check icon.
- `.doc` → `warningContainer` / `warning` text + info icon, label *"Basic"*.

### 5.3 Primary Button

- Height 52, `radius full`, `primary` bg, `onPrimary` text, icon + label.
- Disabled: `surfaceVariant` bg / `onSurfaceVariant` text at 40%.
- Min touch target 48dp.

### 5.4 Secondary / Ghost Button

- Transparent bg, 1dp `outline` border, `onSurface` text. Used for *Cancel* / secondary actions.

### 5.5 Stage Progress (processing)

- Linear progress bar (`primary`) with **stage label** above and **stage chips** showing the pipeline:
  `Sniffing → Parsing → Rendering → Paginating → Printing`.
- Completed stages: `success` check. Current: `primary` pulse. Pending: `onSurfaceVariant` dot.
- Below: **document skeleton** — animated page silhouette using `surfaceVariant` shimmer. Shimmer base `surfaceVariant`, highlight = `surfaceVariant` + 6% white (light) / 6% primary (dark).
- Cancel button (ghost) always visible.

### 5.6 Result Card

- `surface`, `radius lg`, elevation 1.
- Top: `pdfrx` preview inside `viewerBackdrop`, page with `pageShadow`, rounded `md`.
- Below: filename (`mono`), meta row — pages · size · format badge.
- Sticky action bar at bottom: **Save to Device** (primary) + **Share PDF** (secondary).

### 5.7 Snackbar / Status

- Success: `successContainer` bg, `success` icon, `onSurface`-appropriate text.
- Error: `errorContainer` bg, `error` icon. Optional **Retry** action.
- Dark mode: containers are the dark variants; text is `onSurface`.

### 5.8 Password Sheet (encrypted `.docx`)

- Bottom sheet (`radius xl` top), `surface`, elevation 3.
- Lock icon, title *"Password required"*, masked `TextField`, **Unlock** (primary) / **Cancel** (ghost).
- Error state: field border `error`, helper text *"Incorrect password"*.

### 5.9 Banner (legacy `.doc`)

- Inline in result card, `warningContainer`, `warning` icon, text:
  *"Legacy .doc — basic formatting. Images and complex layout may differ."*
- Persistent (not dismissible) so the user is never misled about fidelity.

---

## 6. Screens & Flows

```text
        ┌────────────────┐
        │  Home          │  dropzone · formats · recent
        └───────┬────────┘
   (pick)       │
        ┌───────▼────────┐   encrypted? ──► Password Sheet ──┐
        │  Processing    │                                    │
        └───────┬────────┘                                    │
        (done)  │  (error) ──► Error Card (retry)             │
        ┌───────▼────────┐                                    │
        │  Result        │◄───────────────────────────────────┘
        │  preview·meta  │
        └───┬────────┬───┘
      Save │        │ Share
        ┌───▼──┐  ┌──▼───────┐
        │Saved │  │ Share    │  snackbar + system sheet
        └──────┘  └──────────┘
```

### 6.1 Home / Converter

- `AppBar`: title *doc2pdf*, **theme toggle** (system/light/dark) as an action.
- Hero dropzone.
- Quick row of supported formats (badges).
- **Recent conversions** list (last 5, persisted): filename, relative time, size, format badge; tap → result.
- Footer: *"Files never leave your device."* with a shield icon (`onSurfaceVariant`).

### 6.2 Processing

- Replaces content (no back-swipe during conversion; cancel only).
- Stage progress + skeleton + cancel.
- Screen keeps the device awake (`wakelock`) while converting.

### 6.3 Result

- Preview first, then metadata, then actions.
- Saved automatically → inline *"Saved to Documents/doc2pdf/<name>"* line under the file name; a warning-styled line appears if publishing was blocked (e.g. storage permission declined on Android 8/9).
- Share → `share_plus` sheet.
- Overflow menu: *Convert another*, *Convert again*.

### 6.4 Ads

- **Banner:** anchored adaptive, mounted on the home scaffold's `bottomNavigationBar`, so it persists across the picker, progress and result states. It renders nothing until loaded (no reserved gap, no layout shift), and never sits next to Convert, Preview or Share.
- **Interstitial:** one per successful conversion, capped at one show per 3 minutes; the result screen is already rendered behind it.
- **Consent:** UMP form shown only where legally required; silent elsewhere.
- **Neutrality:** the banner uses the standard AdMob surface, takes no brand colour, and is never styled to look like app content or a button.
- **Failure:** offline or a failed load means no ad — the screen simply looks as it did before.

### 6.5 Empty / Error States

- **Empty recents:** illustration + *"No conversions yet"*.
- **Error card:** icon (`error`), title, message mapped from the error taxonomy (plan.md §Errors), **Retry** + **Choose another file**.

---

## 7. Dark Mode Specification

### 7.1 Behavior

- Follows **system** by default; manual override **System / Light / Dark** persisted (`shared_preferences`).
- Toggle lives in the app bar (home) — a 3-state segmented control in a bottom sheet on tap.
- Theme change animates with `base` (250 ms); no flash of wrong theme on cold start (read persisted value before first frame).

### 7.2 Rules

1. **Never invert document content.** PDF pages and the docx render stay on their true white; only chrome adapts.
2. **Desaturate brand accents.** `primary` shifts from `#4F46E5` → `#A5B4FC` (lighter, lower chroma) to avoid vibration on dark.
3. **Contrast ≥ WCAG AA** for all text: `onSurface` on `background` ≈ 15:1; `onSurfaceVariant` ≈ 7:1; badge text ≥ 4.5:1.
4. **Elevation with tint**, not black-on-black: dark surfaces get `primary` overlays (§2.5).
5. **Borders over shadows** in dark mode — 1dp `outline` reads better than soft shadows.
6. **Skeletons/shimmer** use `primary`-tinted highlight, never white glare.
7. **Status bar / nav bar** follow theme (`SystemUiOverlayStyle`), transparent over `background`.
8. **Images/brand**: the app logo uses a monochrome/duotone mark so it works on both themes.

### 7.3 Theme Mapping (Dart)

```dart
// lib/core/theme/app_colors.dart
class AppColors {
  static const primaryLight        = Color(0xFF4F46E5);
  static const primaryDark         = Color(0xFFA5B4FC);
  static const backgroundLight     = Color(0xFFF8FAFC);
  static const backgroundDark      = Color(0xFF0B0E14);
  static const surfaceLight        = Color(0xFFFFFFFF);
  static const surfaceDark         = Color(0xFF12151C);
  static const surfaceVariantLight = Color(0xFFF1F5F9);
  static const surfaceVariantDark  = Color(0xFF1B1F27);
  static const onSurfaceLight      = Color(0xFF0F172A);
  static const onSurfaceDark       = Color(0xFFE6E9EF);
  static const onSurfaceVariantLight = Color(0xFF475569);
  static const onSurfaceVariantDark  = Color(0xFF9AA3B2);
  static const outlineLight        = Color(0xFFE2E8F0);
  static const outlineDark         = Color(0xFF2A2F3A);
  static const successLight        = Color(0xFF16A34A);
  static const successDark         = Color(0xFF4ADE80);
  static const warningLight        = Color(0xFFB45309);
  static const warningDark         = Color(0xFFFBBF24);
  static const errorLight          = Color(0xFFDC2626);
  static const errorDark           = Color(0xFFF87171);
  static const pageSurface         = Color(0xFFFFFFFF); // always
}

// lib/core/theme/app_theme.dart
ThemeData buildTheme(Brightness b) => ThemeData(
  useMaterial3: true,
  brightness: b,
  colorScheme: ColorScheme.fromSeed(
    seedColor: AppColors.primaryLight,
    brightness: b,
  ).copyWith(
    primary:        b == Brightness.dark ? AppColors.primaryDark  : AppColors.primaryLight,
    surface:        b == Brightness.dark ? AppColors.surfaceDark  : AppColors.surfaceLight,
    surfaceContainerHighest:
                    b == Brightness.dark ? AppColors.surfaceVariantDark : AppColors.surfaceVariantLight,
    onSurface:      b == Brightness.dark ? AppColors.onSurfaceDark : AppColors.onSurfaceLight,
    outline:        b == Brightness.dark ? AppColors.outlineDark   : AppColors.outlineLight,
    error:          b == Brightness.dark ? AppColors.errorDark     : AppColors.errorLight,
  ),
  // typography, shape, spacing applied per §3–§4
);
```

Theme mode resolution:

```dart
MaterialApp(
  theme: buildTheme(Brightness.light),
  darkTheme: buildTheme(Brightness.dark),
  themeMode: ref.watch(themeProvider), // system | light | dark
  // ...
);
```

---

## 8. Accessibility

- **Touch targets** ≥ 48×48 dp; icon buttons carry `tooltip` + `semanticsLabel`.
- **TalkBack order** matches visual order; dropzone announces *"Select a Word document to convert"*.
- **Dynamic type:** layouts use flexible text; badges wrap; no fixed heights on text cards.
- **Reduce motion:** shimmer → static bar; page transitions → fade.
- **Contrast:** verified AA in **both** themes (§7.2.3).
- **State announcements:** conversion start/finish/fail via `SemanticsService.announce`.

---

## 9. Assets & Iconography

- Icons: Material Symbols Rounded, 24dp, 1.5 stroke.
- Key glyphs: `upload_file`, `description`, `picture_as_pdf`, `download`, `share`, `lock`, `shield`, `check_circle`, `error`, `info`.
- Logo: duotone document→PDF mark, works on light/dark.
- Illustrations (empty states): outline style, `onSurfaceVariant`, no heavy fills (dark-friendly).

---

## 10. Copy Deck (microcopy)

| Context | String |
|---|---|
| Dropzone title | Tap to select a Word document |
| Dropzone subtitle | .docx or .doc · stays on your device |
| Processing stages | Sniffing file… · Reading document… · Rendering pages… · Paginating… · Generating PDF… |
| Cancel | Cancel |
| Result title | Your PDF is ready |
| Save | Save to Device |
| Share | Share PDF |
| Saved location line | Saved to Documents/doc2pdf/<name> |
| Legacy banner | Legacy .doc — basic formatting. Images and complex layout may differ. |
| Privacy footer | Your files never leave this device. |
| Ads disclosure | doc2pdf is free and shows ads. Ads never see the files you convert. |
| Error (generic) | Something went wrong. Try again. |
| Error (encrypted) | This document is password-protected. |
| Password title | Password required |

---

## 11. Design QA Checklist

- [ ] Every color referenced from a token, not hardcoded.
- [ ] Light **and** dark reviewed on: home, processing, result, error, password sheet, legacy banner.
- [ ] PDF page stays white in dark mode; backdrop/shadow correct.
- [ ] Contrast AA verified both themes (text, badges, buttons, disabled).
- [ ] Reduce-motion behavior verified.
- [ ] TalkBack labels present on all interactive elements.
- [ ] Theme persists across cold start with no flash.
- [ ] Skeleton/shimmer legible in dark (no white glare).
- [ ] 48dp minimum targets.
- [ ] Status/navigation bars follow theme.
