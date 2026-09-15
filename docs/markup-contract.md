# The markup contract — the stable classes keen-docs emits

The engine and `KeenDocs.Web.View` emit a **stable, bounded set of class names**. Anything that
styles a keen-docs page — the harness CSS, `keendocs.css`, `keendocs-components.css`, a doc_set's
own asset stylesheet — binds to these, and never invents its own.

> Extracted from the former `priv/templates/README.md` when the `calm` template and the
> `/templates/:id/dist/:file` route were removed. The template *mechanism* is gone (superseded by
> the declarative render contract in `KeenDocs.Themes` — see `docs/themes.md`), but this class
> inventory describes the engine's output and outlives it.


Keeping this list stable is what lets any stylesheet render any page.

### Chrome — `kd-*` (emitted by `KeenDocs.Web.View`)
- Top bar: `.kd-top` › `.kd-brand`, `.kd-brand-set`, `.kd-top-link`, `.kd-dd`/`.kd-dd-menu`,
  `.kd-search` (input + button), `.kd-mode` (dark toggle)
- Shell: `.kd-shell` › `.kd-side` (sidebar) + `.kd-main--doc` (doc) or `.kd-main` (plain)
- Sidebar: `.kd-version-l` + `.kd-version` (select); `.kd-nav-sec` (section header);
  `.kd-nav-link` (+ `.active`)
- Home hero: `.kd-hero` › `h1` + `.kd-hero-sub`
- Footer: `.kd-footer` › `.kd-footer-in`
- Misc: `.kd-badge` (+ category modifier), `.kd-toc` (on-this-page)

### Content — `km-*` (engine default profile) + pure-css grid
- Callout: `.km-callout` (info default) / `.km-callout--warning` / `--danger` ›
  `.km-callout__title`, `.km-callout__body`
- Card: `.km-card` › `.km-card__header`, `.km-card__body`
- Showcase: `.km-showcase` › `.km-showcase__title`, `.km-showcase__subtitle`, then a grid
- Columns (KeenDocs.Markup profile → `pa-grid`): `.pc-row` › `.pc-col-*` each ›
  `.km-col__header` (+ `--blue`/`--green`/`--cyan`) + `.km-col__body`
- Code: `.km-code` › `pre.lumis` (colours are **inline** from Lumis — a stylesheet only frames the
  block, never recolours tokens)
- Live demo (keen-docs ext): `.kd-demo` › `.kd-demo-live`, `.kd-demo-source`, `.kd-out`
- Tables: plain `<table>/<thead>/<th>/<td>`

> **Colours come from `--base-*`.** Hardcoding a hex where a `var(--base-*)` exists is a bug — it
> breaks per-doc_set theming. Dark mode is the `.pc-mode-dark` scope in `priv/web/dark-theme.css`,
> which sets `color-scheme: dark` so embedded web components and `light-dark()` code follow, and
> overrides `--base-*` rather than restyling selectors.
