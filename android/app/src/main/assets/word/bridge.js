/*
 * doc2pdf render bridge.
 *
 * Exposes functions called from Kotlin via WebView.evaluateJavascript():
 *   renderFromUrl(url)  - .docx bytes fetched from a WebViewAssetLoader URL
 *   renderFromBase64(b) - .docx bytes inlined as base64 (small files)
 *   renderHtml(html)    - pre-built HTML (legacy .doc via Apache POI)
 *
 * Reports back through the injected `AndroidBridge` object.
 */
(function () {
  "use strict";

  function bridge() {
    return typeof AndroidBridge !== "undefined" ? AndroidBridge : null;
  }
  function progress(phase, pct) {
    var b = bridge();
    if (b && b.onProgress) {
      try { b.onProgress(String(phase), Number(pct)); } catch (e) {}
    }
  }
  function done(pages) {
    var b = bridge();
    if (b && b.onRendered) b.onRendered(Number(pages) || 1);
  }
  function fail(msg) {
    var b = bridge();
    if (b && b.onError) b.onError(String(msg));
  }

  function readOptions() {
    var o = {};
    try {
      if (typeof renderOptions !== "undefined" && renderOptions) o = renderOptions;
    } catch (e) {}
    return o;
  }

  var DEFAULT_OPTIONS = {
    breakPages: true,
    renderHeaders: true,
    renderFooters: true,
    renderFootnotes: true,
    renderEndnotes: true,
    ignoreLastRenderedPageBreak: false,
    useBase64URL: true,
    inWrapper: true,
    experimental: true,
  };

  // Physical page target, in CSS pixels at 96 dpi. A4 is 794 x 1123.
  var PAGE = { widthPx: 794, heightPx: 1123 };

  function reset() {
    var c = document.getElementById("doc");
    c.innerHTML = "";
    c.style.zoom = "";
    return c;
  }

  function ensurePageStyle() {
    var style = document.getElementById("doc2pdf-page-style");
    if (!style) {
      style = document.createElement("style");
      style.id = "doc2pdf-page-style";
      document.head.appendChild(style);
    }
    return style;
  }

  window.configurePage = function (widthMils, heightMils) {
    var w = Number(widthMils);
    var h = Number(heightMils);
    if (!isFinite(w) || !isFinite(h) || w <= 0 || h <= 0) return;

    PAGE.widthPx = (w * 96) / 1000;
    PAGE.heightPx = (h * 96) / 1000;

    var meta = document.querySelector('meta[name="viewport"]');
    if (!meta) {
      meta = document.createElement("meta");
      meta.name = "viewport";
      document.head.appendChild(meta);
    }
    meta.setAttribute(
      "content",
      "width=" + Math.round(PAGE.widthPx) + ", initial-scale=1.0",
    );

    // Android WebView's print path is unreliable with mm/pt @page sizing.
    // Use px here: one CSS px is exactly 1/96 in, so this is still A4.
    ensurePageStyle().textContent =
      "@page { size: " +
      PAGE.widthPx +
      "px " +
      PAGE.heightPx +
      "px; margin: 0; }";

    document.documentElement.style.width = PAGE.widthPx + "px";
    document.documentElement.style.minWidth = PAGE.widthPx + "px";
    document.documentElement.style.margin = "0";
    document.body.style.width = PAGE.widthPx + "px";
    document.body.style.minWidth = PAGE.widthPx + "px";
    document.body.style.margin = "0";
    document.body.style.padding = "0";
  };

  // A document page can be Letter while the user asked for A4 (or vice
  // versa).  Scale the rendered pages to the requested media instead of
  // letting the WebView clip the overflow on both sides.
  function fitToPage(container) {
    var section = container.querySelector(".docx-wrapper > section.docx");
    if (!section) return;
    var docW = section.offsetWidth || section.getBoundingClientRect().width;
    var docH = section.offsetHeight || section.getBoundingClientRect().height;
    if (!docW || !docH) return;

    var scale = Math.min(PAGE.widthPx / docW, PAGE.heightPx / docH, 1);
    if (scale < 0.995) {
      container.style.zoom = String(scale);
    }
  }

  async function renderInto(buffer) {
    progress("rendering", 35);

    var opts = Object.assign({}, DEFAULT_OPTIONS, readOptions());
    var container = reset();

    await docx.renderAsync(buffer, container, null, opts);
    fitToPage(container);

    await settleAndReport();
  }

  async function settleAndReport() {
    progress("paginating", 90);

    // Fonts must settle before printing or line breaks/pagination are wrong.
    try {
      if (document.fonts && document.fonts.ready) {
        await document.fonts.ready;
      }
    } catch (e) {}

    // Let layout run for two frames.
    await new Promise(function (resolve) {
      requestAnimationFrame(function () {
        requestAnimationFrame(resolve);
      });
    });

    var pages =
      document.querySelectorAll(".docx-wrapper > section.docx").length || 1;
    done(pages);
  }

  window.renderFromUrl = function (url) {
    (async function () {
      try {
        progress("parsing", 10);
        var res = await fetch(url);
        if (!res.ok) throw new Error("fetch failed: " + res.status);
        var buf = await res.arrayBuffer();
        await renderInto(buf);
      } catch (e) {
        fail(e && e.message ? e.message : e);
      }
    })();
  };

  window.renderFromBase64 = function (b64) {
    (async function () {
      try {
        progress("parsing", 10);
        var bin = atob(b64);
        var len = bin.length;
        var bytes = new Uint8Array(len);
        for (var i = 0; i < len; i++) bytes[i] = bin.charCodeAt(i);
        await renderInto(bytes.buffer);
      } catch (e) {
        fail(e && e.message ? e.message : e);
      }
    })();
  };

  // Legacy .doc: HTML already built natively (Apache POI). Reuse the same
  // fonts/styles and wrap it in a single page box so it prints consistently.
  async function renderHtmlInternal(html) {
    progress("parsing", 20);
    var container = reset();

    var wrapper = document.createElement("div");
    wrapper.className = "docx-wrapper";

    var section = document.createElement("section");
    section.className = "docx";
    section.style.width = PAGE.widthPx + "px";
    section.style.minHeight = PAGE.heightPx + "px";
    section.style.padding = "72pt";
    section.style.boxSizing = "border-box";
    section.style.background = "#ffffff";
    section.style.color = "#000000";
    section.innerHTML = html;

    wrapper.appendChild(section);
    container.appendChild(wrapper);

    await settleAndReport();
  }

  window.renderHtml = function (html) {
    (async function () {
      try {
        await renderHtmlInternal(html);
      } catch (e) {
        fail(e && e.message ? e.message : e);
      }
    })();
  };

  window.renderHtmlFromUrl = function (url) {
    (async function () {
      try {
        progress("parsing", 15);
        var res = await fetch(url);
        if (!res.ok) throw new Error("fetch failed: " + res.status);
        var html = await res.text();
        await renderHtmlInternal(html);
      } catch (e) {
        fail(e && e.message ? e.message : e);
      }
    })();
  };
})();
