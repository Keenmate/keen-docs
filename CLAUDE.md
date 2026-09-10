# CLAUDE.md

Guidance for Claude Code when working in this repository.

## What this project is

keen-docs is an Elixir/Phoenix **docs + showcase engine** for KeenMate's component libraries — the
"done better" rewrite of `../svelte-docs`. Docs pages are authored in a **custom markdown superset**
and render **real, live component demos that talk to a real server**.

**Read [`DESIGN.md`](./DESIGN.md) first** — it holds the full vision, architecture decisions, the
problems being fixed, and the roadmap. This file is only the working conventions.

## Current state: POC

A plain **Mix** project (not `phx.new` yet) proving the markdown→live-docs pipeline. The rendering
**engine has been extracted** to a sibling library, [`../keen-markdown`](../keen-markdown) (Hex
`keen_markdown`, module root `KeenMarkdown`), consumed here via a path dep. keen-docs is now the engine's
first consumer; it adds only its **docs-specific extensions** (`lib/keen_docs/extensions/`) plus
`lib/keen_docs/poc.ex` as the page shell. A real **Postgres content layer** and a minimal **web test
harness** (Plug/Bandit) now sit on top. See DESIGN.md §8.

```bash
make deps                           # mix deps.get
make poc                            # → build/poc.html (open in a browser)
make dev                            # web test harness → http://localhost:4000 (frees the port first)
make db-gen                         # regenerate KeenDocs.Database.* from the live keen_docs DB
make demo                           # read-only visualizer over the seeded content
mix test                            # keen-docs' own tests; run `mix test` in ../keen-markdown too
```

## Architecture in one breath

One central multi-tenant Phoenix app, bound to many domains (hub `docs.keenmate.dev` + per-package
`web-multiselect.keenmate.dev`), fed by content-only repos published via a Node `keendocs` CLI
(pack+upload, mirroring `../pure-admin-cli`). Central DB for profiles/favorites/notes/fulltext.
Generic, data-shape-oriented endpoints back the live demos. See DESIGN.md §4–5.

## The markdown pipeline (the core — now in `../keen-markdown`)

The engine lives in the `keen_markdown` library. Work on the parser/renderer/behaviour happens **there**,
not here. Its modules (`KeenMarkdown.*`):

- `frontmatter.ex` — split YAML front matter → `{meta, body}`.
- `directive_parser.ex` — **the heart**: pure Elixir, **code-fence-aware** scanner that builds a nested
  `:::` block tree. Node shapes: `{:directive, name, attrs, children}`, `{:markdown, text}`,
  `{:fence, lang, flags, code}`, `{:raw, text}`. Keep it dependency-free. `parse/2` takes the set of
  **raw-body directive** names (from extensions' `raw_directives/0`) whose body is captured verbatim
  as a single `{:raw, text}` child — `:::` depth-counted so a balanced directive example survives.
- `renderer.ex` — node tree → `Output`. Only the dispatch loop, plain markdown and fallbacks live here;
  the authoring vocabulary lives in extensions.
- `output.ex` — the result: **page regions** (`head`/`body`/`footer` + keyed `assets`, `toc`). Rendering
  never returns a bare HTML string.
- `context.ex` — per-render state: extension registry, deterministic demo counter, accumulating output.
  **Never** reach for the process dictionary or any global here.
- `extension.ex` — behaviour: `directives/0`, `raw_directives/0`, `fences/0`, `render/2 → {iodata, ctx}`,
  `document/3` (before body), `finalize/1` (after body). All optional. Cross-block state goes in the
  context's private store, keyed by module.
- `keen_markdown.ex` — the public API: `KeenMarkdown.render/2` → `Output`.
- **generic extensions** (ship in the lib, useful to any content site): `layout` (columns/col/showcase),
  `blocks` (card/callout), `code` (`:::code{lang=…}` — a raw-body highlighted code block), `example`
  (the legacy ` ```lang example ` fence role; keen-docs uses `code` instead), `mermaid`, `open_graph`.

**keen-docs' own extensions** (`lib/keen_docs/extensions/`, docs-specific, plug into the same behaviour):
- `demo` — the live **directives** `:::demo` (mount + show source) and `:::run` (behavior JS bound to the
  preceding demo; scripts go to the footer). Both raw-body. (Liveness is an explicit directive, never a
  fence flag.)
- `cdn_package` — load the documented `web-*` component from jsdelivr, pinned to the doc version.
- `app` — keen-phoenix-svelte islands (`:::app` + `:::props` + `:::placeholder`).
- `poc.ex` — assembles the regions into a standalone HTML page (inlines `keendocs.css`; the engine ships no CSS — it emits `kd-*` classes + inline-styled code, and the consumer owns styling).

The full vocabulary is assembled in `config :keen_markdown, :extensions` = generic set ++ keen-docs' three.

**Adding a block type means writing an extension, not editing the renderer.** A *generic* block (any site
would want it) belongs in `../keen-markdown`; a *docs-specific* one (live components, CDN, islands) belongs
here. Extensions are installed server-side; content repos stay pure data and never ship Elixir.

### Rendering target is pluggable (HTML today, HEEx proven)

The parser/renderer are output-format-agnostic — the extension set decides the target. HTML mode:
`:::card` → `<div class="kd-card">`. HEEx mode (for a Phoenix portal like keen_pure_admin): `:::card` →
`<.card>` component tags the consumer compiles (`Phoenix.LiveView.TagEngine.compile/2`) against its design
system. keen_markdown stays **Phoenix-free** — it only emits strings. See DESIGN.md §5 "Rendering targets"
and §8 for the proven spikes (`transform_markdown` for redefining `##`; DB-content→`<.card>`; cached route;
`{{vars}}`; compile-boundary safety = sentinel→neutralize→swap).

### POC spikes live in `tmp/` (gitignored, throwaway)

Runtime/HEEx experiments live under `tmp/heex_proof` and `tmp/keen_docs_p1` — scratch projects, not part
of the build. The **findings** are recorded in DESIGN.md §8; the code is disposable. Don't rely on them.

### Authoring model (keep these invariants)

- **Layout is generic and decoupled from demos.** `:::columns{cols="80/20"}` + `:::col{title=…}` is
  pure layout (CSS grid `fr` ratios, not Bootstrap 12-grid). "Demo-ness" is an **explicit directive**
  (`:::demo` / `:::run`), never a column and never a fence role. Code display is `:::code{lang=…}`; a
  plain ` ```lang ` fence still renders as a code block, but role flags (`demo`/`run`/`example`) were
  retired — the fence header carried two orthogonal things (language + role), which was the confusion.
- `:::showcase` is only a **preset** over `:::columns` (positional accent colors). `:::col` = labelled
  column (no chrome); `:::card` = boxed. Don't collapse these back into a fixed 3-column component.
- Demos are usually **markup + a CDN web component pinned to the doc version**, not compiled apps.
  Islands (keen-phoenix-svelte) are the rare case.

## Database & web layer

Persistence is **stored SQL functions + raw Postgrex + code generation — no Ecto** (mirrors
`../keen-auth-permissions`). Don't reach for Ecto schemas/queries.

- **The SQL lives in `../keen-docs-database`** (managed by **debee**), NOT here. The keen_docs content
  domain is `100_docs_content.sql` (`public.doc_set → doc_variant → document` + content-addressed
  `content_blob`; `const` lookups `doc_set_kind`/`package_ecosystem`/`version_maturity`), example seed
  is `999_examples.sql` (swept, recreated every `make setup`). Authored to the **Bliss PostgreSQL
  guidelines** — verbs from the registry (`ensure`, not "ingest"), tables in `public`, audit columns
  first, `search_*` two-jsonb signature, public-API types only. See that repo's CHANGELOG.
- **`db-gen`** (vendored `db-gen-win.exe`/`db-gen-linux` + `db-gen.json` + `db-gen/*.gotmpl`, retargeted
  to `KeenDocs.Database`) reads those functions → generates typed wrappers into `lib/keen_docs/database/`
  (committed). `public`-schema functions get no prefix. **Regenerate after changing the SQL** — the loop
  is `make setup` (in keen-docs-database) → `make db-gen` (here). Both need the DB reachable (VPN to
  `db-01.km8.local`).
- **`KeenDocs.Repo`** is a thin Postgrex wrapper (`query/2`, `child_spec/1`, `after_connect` sets
  `search_path`); **`KeenDocs.PostgrexTypes`** enables jsonb-as-map via Jason; **`KeenDocs.Content`**
  (`use KeenDocs.Database, repo: KeenDocs.Repo`) is the content API.
- **Web harness** — `KeenDocs.Application` supervises `KeenDocs.Repo` + Bandit(`KeenDocs.Web.Router`).
  It's Plug (Phoenix's substrate), deliberately minimal so it promotes to `phx.new` + LiveView without
  rework. Keep handlers thin — data shape comes from the DB (`kind_code`/`show_in_path`/`applies_to`),
  never hardcoded per content type. The `Makefile` `kill-port` target mirrors `../web-multiselect`.
- The **middle content layer is `doc_variant`** (neutral on purpose): a version for components, a
  division (azure/aws) for infrastructure, a hidden `main` for guides. Don't reintroduce a component-only
  "version"/"package" vocabulary.

## Front-end runtime — `window.pureCss`

keen-docs is a **pure-css-only** consumer (no pure-admin dependency). The app shell *and* its JS
runtime live in `@keenmate/pure-css` (rc05+), vendored to `priv/web/vendor/pure-css/` by
`make vendor-css` (local sibling) or `make vendor-css-npm` (the pinned `PURE_CSS_VERSION`).

**pure-css owns the foundation runtime; keen-docs does not wrap it.** `window.pureCss` provides the
event bus, `viewport` (the single throttled resize source), `colorScheme` (the single
`prefers-color-scheme` watcher), `device`, `overlay`, `menus`, `config`, `debug`, and the
`components` registry with the shell engines (fit, navbar-dropdown, sidebar-resize,
container-breakpoint).

Note the contrast with the *other* consumer: `pure-admin` repacks the same runtime behind
`window.pureAdmin` as an **adopt-and-extend facade** (buses adopted by reference,
`components = Object.create(pureCss.components)` for read-through) because it layers its own
components — toast, tooltips, splitter, overflow — on top. **keen-docs deliberately has no such
facade**: it ships no components of its own, so the indirection would buy nothing. Call sites name
`window.pureCss` directly, guarded. Don't introduce a `window.keenDocs` namespace without a
concrete set of keen-docs-owned components to justify it.

### Invariants

- **Never re-create what pure-css owns.** Before writing a listener or a watcher, check
  `priv/web/vendor/pure-css/pure-css.js` for an existing owner.
- **Never add a second `window.resize` listener** — subscribe to `viewport:resize`. An *element*
  box still needs its own `ResizeObserver`.
- **Never open a second `prefers-color-scheme` matchMedia** — read `pureCss.colorScheme.mode` and
  subscribe to `colorscheme:change`. A one-shot read is the subtler version of this bug: "auto"
  mode must keep following the OS, not sample it once.
- **One owner per preference** (mode / font-size / font-family / sidebar). Controls call the owner's
  API; they never toggle the class or touch `localStorage` themselves. pure-css exposes **no**
  storage module, so the `kd-*` `localStorage` helpers in `settings-panel.js` are legitimately
  keen-docs' own — that is not duplication.
- **Single-source rule:** a value that also exists as a CSS token is read from the token, never
  re-typed as a JS literal — the mobile breakpoint comes from `pureCss.config.mobileBreakpoint`
  (itself read from `--pc-mobile-breakpoint`), not a bare `768`. The exception is a CSS `@media`
  query, which cannot read a custom property.
- **Don't conflate `config.mobileBreakpoint` with `device.class`.** The first is a layout *width*
  (sidebar → overlay); the second is *what kind of machine this is* (a narrowed desktop window is
  still `desktop`). "Should this be a fullscreen sheet?" is a `device` question.
- **Header items shed by declared priority, not media queries** — give the slot `data-pc-fit="hide"`
  + `data-pc-fit-priority`; the fit engine measures the real row.
- **Script order matters.** The `pure-css/*.js` tags come first; keen-docs' inline `layout_js` and
  `settings-panel.js` follow, so `window.pureCss` is installed before they run. The one script that
  must precede everything is the pre-paint `pref_init_js` in `<head>` — it beats the first paint, so
  it is the *only* sanctioned place to read `localStorage` / `matchMedia` directly.
- **No new inline `<script>` strings in View** beyond what is already there; new behaviour goes in
  `priv/web/keendocs/*.js`.
- `priv/web/vendor/pure-css/*` is **vendored, not authored** — change `../pure-css` and re-vendor.

## Conventions

- **Elixir 1.20 / OTP 29** (installed via Homebrew; `mix.exs` still declares `~> 1.15`). Idiomatic
  Elixir; small focused modules; pattern-match over conditionals.
- **Markdown engine**: MDEx (comrak Rust NIF, precompiled) + **lumis** for highlighting. Highlighting is
  opt-in and the engine isn't bundled — `{:lumis, "~> 0.1"}` + `config :mdex_native, syntax_highlighter: :lumis`.
- **Server-side rendering only** for content/highlighting — no client-side re-highlighting, no FOUC hacks
  (that was a svelte-docs anti-pattern we're explicitly removing).
- Never reintroduce a **global mutable singleton** for config/state (svelte-docs' SSR leak). Keep state
  request/domain-scoped.
- Rendering must stay **deterministic** — the same document renders to the same bytes. Ingestion relies
  on content hashing (DESIGN.md §4), so never use `System.unique_integer/1` or timestamps in output.
- When adding content features, update `priv/content/form-integration.md` (the exercise-everything sample),
  add tests under `test/`, and re-run the POC build to verify.

## Persistent design memory

The architecture of record lives in [`DESIGN.md`](./DESIGN.md) — update it when decisions change.
Cross-session context that is *not* derivable from the repo (toolchain quirks, authoring-style
preferences) lives in the memory dir indexed by
`~/.claude/projects/C--Git-KM-keen-docs/memory/MEMORY.md`.

## Related repos (siblings under C:\Git\KM)

`../keen-markdown` (**the extracted rendering engine — the core lives there now**) · `../svelte-docs`
(predecessor) · `../keen-phoenix-svelte` (island mounter) · `../pure-admin-cli` (CLI to mirror) ·
`../web-multiselect` (flagship web component, ships CEM) · `../keen-auth-permissions` (auth) ·
`../cafeindustrial-cz` (Phoenix portal — a candidate second consumer of `keen_markdown`).
