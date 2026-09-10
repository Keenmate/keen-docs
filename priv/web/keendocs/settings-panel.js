/**
 * keen-docs settings panel
 *
 * A floating offcanvas drawer (keen-docs' own `.kd-settings-panel` chrome, styled by keendocs-components.css) that
 * drives the reader-facing preferences keen-docs actually supports: appearance (light/dark/auto),
 * font size, font family, and the sidebar (docked/hidden + drag-to-resize). All state persists to
 * localStorage under `kd-*` keys and is applied WITHOUT a reload.
 *
 * Split of responsibilities: mode + font-size are restored PRE-PAINT by the inline head script
 * (both toggle a class on <html>, so restoring them late would reflow) — this script only reflects
 * them into the controls. Font-family and the sidebar states are restored here.
 *
 * This is keen-docs' own script (its control set differs from pure-admin's demo panel — no theme
 * manifests, container width, RTL or profile options), so it is NOT vendored from pure-admin.
 */
(function () {
  'use strict';

  // Font family → a --base-font-family stack. Every consumer (chrome, kd-* content, embedded
  // components) reads --base-font-family, so one override re-fonts the whole page.
  var FONT_STACKS = {
    serif: 'Georgia, "Times New Roman", Times, serif',
    mono: '"Courier New", Courier, monospace',
    manrope: '"Manrope", system-ui, sans-serif',
    'maven-pro': '"Maven Pro", system-ui, sans-serif',
    signika: '"Signika", system-ui, sans-serif'
  };
  // The ones that need a webfont pulled from Google Fonts (system/serif/mono don't).
  var GOOGLE_FONTS = {
    manrope: 'Manrope:wght@400;500;600;700',
    'maven-pro': 'Maven+Pro:wght@400;500;600;700',
    signika: 'Signika:wght@400;500;600;700'
  };
  var loadedFonts = {};

  function store(key, val) {
    try {
      localStorage.setItem(key, val);
    } catch (e) {}
  }
  function drop(key) {
    try {
      localStorage.removeItem(key);
    } catch (e) {}
  }
  function get(key) {
    try {
      return localStorage.getItem(key);
    } catch (e) {
      return null;
    }
  }

  function ready(fn) {
    if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', fn);
    else fn();
  }

  ready(function () {
    var panel = document.getElementById('kdSettingsPanel');
    if (!panel) return;

    var html = document.documentElement;
    var body = document.body;
    var toggle = document.getElementById('kdSettingsToggle');
    var modeSel = document.getElementById('kdModeSelector');
    var fontSizeSel = document.getElementById('kdFontSizeSelector');
    var fontFamilySel = document.getElementById('kdFontFamilySelector');
    var behaviorSel = document.getElementById('kdSidebarBehaviorSelector');
    var resizableChk = document.getElementById('kdSidebarResizable');
    var resetBtn = document.getElementById('kdResetSettings');
    var sidebar = document.querySelector('.pc-layout__sidebar');

    // ── open / close ────────────────────────────────────────────────────────
    if (toggle) {
      toggle.addEventListener('click', function (e) {
        e.stopPropagation();
        panel.classList.toggle('kd-settings-panel--open');
      });
    }
    // Dismiss on an outside click (the toggle's stopPropagation keeps its own click from closing it).
    document.addEventListener('click', function (e) {
      if (panel.classList.contains('kd-settings-panel--open') && !panel.contains(e.target)) {
        panel.classList.remove('kd-settings-panel--open');
      }
    });

    // ── appearance (light / dark / auto) ──────────────────────────────────────
    // Shares the `kd-mode` key + `pc-mode-dark` class with the header toggle button and the
    // pre-paint head script. Restored pre-paint; here we only reflect + apply on change.
    // `auto` means "follow the OS, live". pureCss.colorScheme is the single owner of the
    // prefers-color-scheme watcher — read it rather than opening a second matchMedia here.
    function osPrefersDark() {
      return window.pureCss && pureCss.colorScheme
        ? pureCss.colorScheme.mode === 'dark'
        : matchMedia('(prefers-color-scheme:dark)').matches;
    }
    function applyAutoMode() {
      html.classList.toggle('pc-mode-dark', osPrefersDark());
    }
    // Re-apply whenever the OS flips, but only while no explicit choice is stored — a stored
    // light/dark must survive an OS change.
    if (window.pureCss && pureCss.events) {
      pureCss.events.on('colorscheme:change', function () {
        if (!get('kd-mode')) applyAutoMode();
      });
    }

    if (modeSel) {
      modeSel.value = get('kd-mode') || 'auto';
      modeSel.addEventListener('change', function () {
        var m = modeSel.value;
        if (m === 'dark') {
          html.classList.add('pc-mode-dark');
          store('kd-mode', 'dark');
        } else if (m === 'light') {
          html.classList.remove('pc-mode-dark');
          store('kd-mode', 'light');
        } else {
          drop('kd-mode');
          applyAutoMode();
        }
      });
    }

    // ── font size (rescales the <html> rem base via .font-size-*) ──────────────
    // Applied pre-paint by the head script; reflect only.
    if (fontSizeSel) {
      fontSizeSel.value = get('kd-font-size') || 'default';
      fontSizeSel.addEventListener('change', function () {
        var s = fontSizeSel.value;
        html.classList.remove('font-size-small', 'font-size-default', 'font-size-large', 'font-size-xlarge');
        if (s && s !== 'default') html.classList.add('font-size-' + s);
        store('kd-font-size', s);
      });
    }

    // ── font family (--base-font-family override) ─────────────────────────────
    function applyFontFamily(family) {
      if (family && family !== 'default' && FONT_STACKS[family]) {
        loadGoogleFont(family);
        html.style.setProperty('--base-font-family', FONT_STACKS[family]);
      } else {
        html.style.removeProperty('--base-font-family');
      }
    }
    function loadGoogleFont(family) {
      if (!GOOGLE_FONTS[family] || loadedFonts[family]) return;
      var link = document.createElement('link');
      link.rel = 'stylesheet';
      link.href = 'https://fonts.googleapis.com/css2?family=' + GOOGLE_FONTS[family] + '&display=swap';
      document.head.appendChild(link);
      loadedFonts[family] = true;
    }
    if (fontFamilySel) {
      var savedFamily = get('kd-font-family') || 'default';
      fontFamilySel.value = savedFamily;
      applyFontFamily(savedFamily); // restored here (not pre-paint) — a font swap is cheap vs a reflow
      fontFamilySel.addEventListener('change', function () {
        applyFontFamily(fontFamilySel.value);
        store('kd-font-family', fontFamilySel.value);
      });
    }

    // ── sidebar behavior (docked / hidden) ────────────────────────────────────
    // `body.sidebar-hidden` collapses the docked sidebar to width:0 (core.css) so the content
    // reclaims the space; the panel itself is the way back to Docked. Independent of the mobile
    // `body.sidebar-visible` overlay driven by the burger (kdToggleSidebar).
    var hidden = get('kd-sidebar-hidden') === 'true';
    body.classList.toggle('sidebar-hidden', hidden);
    if (behaviorSel) {
      behaviorSel.value = hidden ? 'hidden' : 'normal';
      behaviorSel.addEventListener('change', function () {
        var hide = behaviorSel.value === 'hidden';
        body.classList.toggle('sidebar-hidden', hide);
        store('kd-sidebar-hidden', hide ? 'true' : 'false');
      });
    }

    // ── sidebar resizable (drag-to-resize handle) ─────────────────────────────
    // Default ON (keen-docs' prior always-resizable behavior). Adds/removes the `--resizable` class
    // that pure-css's sidebar-resize.js keys off, then (re)inits or strips the handle.
    function sidebarResize() {
      return window.pureCss && pureCss.components && pureCss.components.sidebarResize;
    }
    function applyResizable(on) {
      if (!sidebar) return;
      if (on) {
        sidebar.classList.add('pc-layout__sidebar--resizable');
        var sr = sidebarResize();
        if (sr && sr.init) sr.init();
      } else {
        sidebar.classList.remove('pc-layout__sidebar--resizable');
        var handle = sidebar.querySelector('.pc-sidebar-resize');
        if (handle) handle.remove();
      }
    }
    var resizable = get('kd-sidebar-resizable') !== 'false'; // default true
    applyResizable(resizable);
    if (resizableChk) {
      resizableChk.checked = resizable;
      resizableChk.addEventListener('change', function () {
        applyResizable(resizableChk.checked);
        store('kd-sidebar-resizable', resizableChk.checked ? 'true' : 'false');
      });
    }

    // ── reset ─────────────────────────────────────────────────────────────────
    if (resetBtn) {
      resetBtn.addEventListener('click', function () {
        ['kd-mode', 'kd-font-size', 'kd-font-family', 'kd-sidebar-hidden', 'kd-sidebar-resizable', 'sidebar-width'].forEach(drop);
        var sr = sidebarResize();
        if (sr && sr.reset) sr.reset();
        location.reload();
      });
    }
  });
})();
