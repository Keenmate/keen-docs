# keen-docs themes & rendering — mechanism plan

> ⚠️ **SUPERSEDED (2026-08-30) for the CSS/bundle half.** keen-docs is now **`@keenmate/pure-css`-only
> with no pure-admin dependency**: the pc-\* app shell + JS runtime come from pure-css, chrome components
> are keen-docs' own `kd-*` (`priv/web/keendocs-components.css`), and the **pure-admin theme stylesheet
> bundles were dropped** (no `priv/web/vendor/themes/`, `seed_from`, `overlay?`, `/themes/…` routes).
> What survives — and is still accurate below — is the **declarative render contract** (`render_block/1`
> + `@render_defaults`: pageHead / toc / regions / header composition / fonts / brand / versionControl),
> now keyed on a plain contract name in `keendocs.json`. Read the sections below as the render-layer plan;
> ignore the CSS-bundle install/lock/overlay plumbing. See CHANGELOG (2026-08-30) + `../DESIGN.md §5`.

Status: **render contract implemented; CSS theme bundles removed (pure-css-only).** This extends
[`../DESIGN.md`](../DESIGN.md); update both when decisions change.

## The idea in one breath

keen-docs replicates **pure-admin's whole themes mechanism** (declare → install → lock → build →
pack), but keen-docs themes are **a bit more than CSS**: on top of the pure-admin theme bundle
(palette + components + modes + variants) they carry a small **declarative render layer** that can
slightly **redefine how a page is assembled** server-side (hero band, breadcrumbs, TOC placement,
region toggles, layout variant). The whole thing is managed by a future **`keendocs` CLI** —
`pure-admin-cli` mirrored, with a docs-flavoured feature set (it also packs/uploads content and
validates the render contract).

## Model

```
pure-admin-core  →  vendored core.css            = BASELINE (full framework + baked default theme,
                                                    the fallback when no theme is selected)
pure-admin theme →  <id>.css bundle              = PALETTE + components, per mode/variant (copied
   (../pure-admin-themes)                           from the pure-admin theme, whole mechanism)
keen-docs theme  =  <id>.css  +  keendocs render block
                                                 = the bundle ABOVE + declarative page-assembly
                                                   directives the View interprets
doc / frontmatter →  title, tagline, crumb path, TOC entries
                                                 = the DATA that fills the shell (theme-independent)
```

### The clean split (the key decision)

- **Doc / frontmatter = the data** — title, tagline, breadcrumb path, TOC entries, badges. From
  content; theme-independent.
- **Theme = CSS palette + a declarative render block** — *whether* there's a hero and where, *whether*
  breadcrumbs render and how, where the TOC sits, which regions appear, which layout variant. The
  theme decides **presentation of the shell**; the doc supplies **what fills it**.

### Guardrail (non-negotiable)

The render layer is **declarative and bounded** — a fixed vocabulary of options / region-toggles /
named layout variants the View understands. Themes do **not** ship executable layout code (keeps
keen-docs' deterministic, no-RCE invariants). If a theme ever needs true custom layout markup, it
must go through the proven **safe compile boundary** (sentinel → neutralize → swap; see DESIGN §8 /
the heex-rendering note) — never raw eval. This render contract is exactly what makes the keendocs
CLI's feature set differ from pureadmin's.

## Anatomy of a keen-docs theme

Mirrors a pure-admin theme, plus a `keendocs` block:

```
themes/<id>/
  theme.json          # pure-admin manifest (name, id, modeCssClass, variantCssClass,
                      #   colorVariants[].modes[].colors) + a `keendocs` render block (below)
  src/scss/<id>.scss  # sets $base-* from the palette → @import pure-admin-core → emits the bundle
  dist/<id>.css       # compiled full framework + palette (modes: pc-mode-*, variants: pa-color-*)
  assets/             # bundled fonts etc.
```

The `keendocs` render block (declarative, initial vocabulary — grow as needed):

```jsonc
"keendocs": {
  "contract": "1.0",
  "layout": "full-width-3pane",     // | "centered" | "reading" — named layout variants
  "pageHead": { "hero": true, "crumbs": true, "badges": true, "subtitleFrom": "description" },
  "toc": { "show": true, "placement": "right-rail" },   // | "inline" | "off"
  "regions": { "sidebar": true, "footer": true, "search": "center" },
  "fonts": { "source": "google", "heading": "...", "body": "...", "mono": "...", "href": "..." }
}
```

`KeenDocs.Web.View` reads this to assemble the page (it already has `page_hero`/breadcrumb/region
plumbing — those become theme-driven instead of hardcoded). Missing keys fall back to core defaults.

#### Render-block vocabulary (contract v1.0 — implemented)

The block is **loaded** by `KeenDocs.Themes.render_block/1` (defaults ← manifest `themes.<id>.keendocs`
← the theme's own `theme.json` `keendocs`; nested keys deep-merge, so a partial block keeps sibling
defaults) and **interpreted** by `View.layout/3`. The full vocabulary and its baseline defaults:

| key | values | default | effect |
|-----|--------|---------|--------|
| `layout` | `"default"` \| any slug | `"default"` | adds a `kd-layout--<slug>` hook class on `.pa-layout` |
| `pageHead.hero` | bool | `true` | `true` = full hero band; `false` = a plain crumb + `<h1>` head |
| `pageHead.crumbs` | bool | `true` | render the breadcrumb |
| `pageHead.badges` | bool | `true` | render the kind/version badges |
| `toc.show` | bool | `false` | render a table of contents from the doc headings |
| `toc.placement` | `"off"` \| `"inline"` \| `"right-rail"` | `"off"` | where the TOC sits (right-rail = a 2-col grid) |
| `regions.sidebar` | bool | `true` | `false` hides the nav sidebar (content runs wide) |
| `regions.footer` | bool | `true` | `false` hides the page footer |
| `regions.search` | `"center"` \| `"off"` | `"center"` | header search box (start/end positions deferred) |
| `fonts` | `{href, body, heading, mono}` \| `null` | `null` | a `<link>` + `--base-font-family`/`-mono` + `--kd-heading-font` |
| `brand` | `{logo, label}` \| `null` | `null` | navbar logo (a theme asset) + label, replacing the `keen-docs` wordmark |
| `versionControl` | `{type:"web-multiselect", module, style, label}` \| `null` | `null` | render the sidebar version switcher as a live `<web-multiselect>` (else the native `<select>`); loads the component + navigates on change |
| `header.nav` | `"hub"` \| `"off"` | `"hub"` | show the hub top-nav (`pa-header__nav`) in `pa-header__start` |
| `header.links` | `"show"` \| `"off"` | `"show"` | show the per-doc_set `header_links` in `pa-header__end` |
| `header.resolve` | bool | `true` | show the "Resolve package.json →" utility link |
| `header.modeToggle` / `header.profile` | bool | `true` | show the dark-mode toggle / profile button |
| `header.cta` | `{label, url, icon, style}` \| `null` | `null` | a primary call-to-action (`pa-btn--<style>`, default `primary`) pinned in `pa-header__end` |

The **data** the head fills with (title, crumb, subtitle, badges) is passed by the router as
`opts[:page]`, and the TOC source as `opts[:toc]` (`output.toc`) — the doc supplies *what*, the block
decides *how*. Where a theme carries its `keendocs` block: for upstream pure-admin themes (which lack
one) declare it in `keendocs.json` under `themes.<id>.keendocs` (nato ships a right-rail TOC there);
a native keen-docs theme would put it in its own `theme.json`.

## The mechanism (pure-admin flow, keendocs-driven)

- **Manifest** (`keendocs.json`, mirrors `pureadmin.json`): `themesDir` + declared themes `{ "<id>": {} }`.
- **Lock** (`keendocs.lock.json`): resolved versions.
- **CLI verbs** (keendocs, mirroring pureadmin): `themes add / install / update / ci / build / pack`.
- **Co-dev source**: the `../pure-admin-themes` sibling (all 15 theme sources) via a `--path`
  override — no registry needed while building.
- **Install shape**: `themesDir/<id>/{theme.json, dist/<id>.css, assets/}`.
- **Selection**: one global default (`config :keen_docs, :theme`), overridable per doc_set via
  `settings["theme"]["id"]`; `nil`/`"none"`/uninstalled → the vendored `core.css` baseline. The same
  `settings["theme"]` map's `accent`/`vars` keys stay a per-doc_set micro-override on top of the
  bundle. Modes via `pc-mode-*` (bare class, `<html>` toggle), variants via `pa-color-*`.

## Current state (this session)

- [x] Vendored pure-admin **core** as `priv/web/vendor/pure-admin/core.css` (baseline/default).
- [x] 10px rem base fixed via pure-css `reboot.css` + `scrollbars.css` (vendored, inlined).
- [x] Pure-admin **page shell** emitted by `View.layout/3` (`pa-navbar`/`pa-layout`/`pa-sidebar`/
      `pa-footer` + `pa-layout__main__inner`), sidebar as `pa-sidebar__nav`, in-content page head.
- [x] **Profile panel** wired (vendored `profile-panel.css` + markup + JS).
- [x] Template resolution skeleton (`config :keen_docs, :template` + per-doc_set override + safe route).
- [~] Hand-extracted `layout.css` / `profile-panel.css` fragments — **to be superseded** by `core.css`
      + theme bundles (they were the wrong unit; kept working meanwhile).

## Tasks

### Phase 1 — collapse onto the core bundle (baseline) ✅ done
- [x] Rewire `View.styles/1` + `layout/3` head to link the single **framework bundle** (`core.css`)
      instead of the base/reboot/scrollbars inline + `layout.css` + `profile-panel.css` links.
- [x] ~~Keep `grid.css` linked~~ — **core.css already carries grid + utilities** (`.pc-col-*`,
      `.pc-row`, `.d-flex`, all 94 `--base-*` vars, the 10px base), so grid/utilities links were
      dropped too; keen-docs content CSS still layers after (inline `<style>`).
- [x] Add `make vendor-pa-core` (copies `../pure-admin/packages/core/dist/css/main.css`).
- [x] Add router route `/vendor/pure-admin/:file`.
- [x] Verify navbar / sidebar / panel / content all render from `core.css` alone (harness: all pages
      200, one core link, full chrome markup, 10px base served). Fragments now **unreferenced**
      (physical removal deferred to Phase 5).

### Phase 2 — themes as copies of pure-admin themes ✅ done
- [x] Add `keendocs.json` manifest (`themesDir: priv/web/vendor/themes`, `source: ../pure-admin-themes`,
      declared themes `nato`, `dracula`, `corporate`). No "keen default" — the core.css baseline IS the
      default; themes are opt-in.
- [x] Seed `themesDir/<id>/` by copying bundles from `../pure-admin-themes/<id>` (theme.json + dist +
      assets) via `KeenDocs.Themes.seed_from/1` + `make seed-themes` (writes `keendocs.lock.json`) —
      the manual stand-in for `keendocs themes install`.
- [x] Router: serve installed theme CSS (`/themes/:id/dist/:file`) + bundled assets/fonts
      (`/themes/:id/assets/*`) from `themesDir`, traversal-guarded, content-type by extension.
- [x] Theme resolution: `theme id` → link `/themes/<id>/dist/<id>.css` instead of `core.css`
      (`KeenDocs.Themes.installed?` guards; uninstalled → baseline).
- [x] **Naming decision**: the bundle selector moved from `:template`/`settings["template"]` to
      **`config :keen_docs, :theme` + `settings["theme"]["id"]`** (pure-admin nomenclature). It sits in
      the SAME `settings["theme"]` map as the existing per-doc_set `accent`/`vars` micro-override — so
      `id` picks the base bundle and `accent`/`vars` fine-tune it. (The legacy `priv/templates` route
      and the `calm` skin were retired — see below.)
- [x] **Modes** already work theme-agnostically — bundles scope dark as a bare `.pc-mode-dark`, which
      keen-docs' existing `<html>` toggle (`mode_init_js` + `mode_toggle_html`) drives; no html-vs-body
      reconcile needed. **Variant**: default `pa-color-*` class is server-rendered on `<html>` from
      `theme.json`; seeded themes are single-variant (`id:""`) so it's plumbing-only for now (an
      interactive `pa-color-*` variant selector is deferred until a multi-variant theme is installed).

### Phase 3 — the render layer (declarative) ✅ done
- [x] Define the `keendocs` render-block schema (contract v1.0) + defaults; document the vocabulary
      (table above). Defaults live in `KeenDocs.Themes.@render_defaults` and reproduce the baseline.
- [x] Load the active theme's block server-side (`KeenDocs.Themes.render_block/1`, deep-merged) and
      expose it to `View` (`View.render_block/1` per request — no global state, deterministic).
- [x] Make `View.layout/3` **theme-driven**: page head (`page_head_region`/`render_page_head` off
      `opts[:page]` data + `pageHead` flags), TOC (`content_region`/`toc_html` off `opts[:toc]` +
      `toc` block), region toggles (sidebar/footer/`search_form`), layout variant class.
- [x] Fonts from the render block (`font_head/1`: `<link>` + `--base-font-family`/`-mono`/`--kd-heading-font`).
- [x] Fallbacks: every key defaults to the baseline when absent (verified — themeless page byte-for-byte
      unchanged: hero band, no TOC, search on, footer on, no font override). Deterministic (disk reads only).

### Phase 4 — the `keendocs` CLI (mirrors pure-admin-cli, docs feature set)
- [ ] Scaffold the `keendocs` CLI (sibling repo/package), mirroring `pure-admin-cli` structure.
- [ ] `themes add / install / update / ci / build / pack` over `keendocs.json` + `keendocs.lock.json`,
      `--path` local override for co-dev.
- [ ] Validate the **render contract** (the keendocs-specific bit pureadmin lacks).
- [ ] (Later) content `pack` + `upload` — the other half of the CLI (DESIGN §CLI).

### Phase 5 — cleanup
- [ ] Remove the superseded hand-extracted `layout.css` / `profile-panel.css` once `core.css` +
      theme bundles cover them.
- [x] **`calm` retired.** Removed `priv/templates/` (the `calm` skin, its manifest and preview) plus
      the `/templates/:id/dist/:file` route and `send_template_css/3`. It was linked by no rendered
      page — `View` never emitted it — and its whole category is gone: `KeenDocs.Themes` ships a
      declarative render contract, not CSS bundles. It had also drifted badly off the `--base-*`
      contract (85 property-level colour literals; only 13 of its 34 `--calm-*` tokens derived from
      `--base-*`, so the "gradient re-tints per doc_set" claim held for one of four stops).
      The class inventory from `priv/templates/README.md` survives as
      [`docs/markup-contract.md`](./markup-contract.md).
- [ ] Update DESIGN.md to the final model.

## Open questions
- Manifest name/location: `keendocs.json` at repo root + `themesDir: priv/web/vendor/themes`? (leaning yes)
- Initial theme set to seed.
- Registry story for real installs (pureadmin.io vs a keendocs registry) — deferred; `--path` for now.
