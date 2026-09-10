defmodule KeenDocs.Web.View do
  @moduledoc "HTML building for the test harness — layout chrome + small helpers."

  alias KeenMarkdown.{HTML, Output}
  alias KeenDocs.Content

  @doc "HTML-escape."
  defdelegate esc(s), to: HTML

  @doc "A document's URL — omits the variant segment when `show_in_path` is false (guides)."
  def doc_path(set, _variant, slug, false), do: "/#{set}/#{slug}"
  def doc_path(set, variant, slug, _true), do: "/#{set}/#{variant}/#{slug}"

  @doc "Render stored markdown to page regions via keen_markdown."
  def render_markdown(content), do: KeenMarkdown.render(content)

  @doc """
  Full page. `opts[:head]` / `opts[:footer]` inject renderer regions for doc pages.
  `opts[:docset]` (a `get_doc_set` row) supplies per-set chrome — accent, header links,
  footer. `opts[:sidebar]` (pre-rendered nav HTML) turns the body into a two-column shell.
  """
  def layout(title, inner, opts \\ []) do
    docset = opts[:docset]
    # The active theme's declarative render contract drives page assembly (page head, regions, TOC,
    # layout variant, fonts). Defaults reproduce the baseline, so a themeless page is unchanged.
    rb = render_block(docset)
    regions = rb["regions"] || %{}

    # Sidebar: present in opts AND not turned off by the theme.
    sidebar = opts[:sidebar]

    aside =
      if Map.get(regions, "sidebar", true) != false do
        # Always render a sidebar host — even sidebar-less pages need the fit-nav OVERFLOW
        # target (#kd-nav-overflow) so the top-nav can fold into the sidebar as the header narrows.
        # The empty host and an otherwise-empty aside self-hide via :has() (see harness_css), so the
        # hub still reads full-width until items actually overflow into it.
        overflow_host = ~s(<nav class="pc-sidebar__nav kd-nav-overflow-host"><ul id="kd-nav-overflow"></ul></nav>)
        # Drag-to-resize is now a reader SETTING (default on): the settings panel adds/removes
        # `pc-layout__sidebar--resizable` (sidebar-resize.js keys off it to append the handle + write
        # --pc-local-sidebar-width). Server-render WITHOUT it so the panel is the single source of that
        # state. Full-height + internal scroll still come from the sticky app-shell (body.pc-layout--sticky).
        ~s(<aside class="pc-layout__sidebar kd-sidebar">#{overflow_host}#{sidebar || ""}</aside>)
      else
        ""
      end

    # Content runs wider when the page ships no sidebar content of its own (the empty host self-hides).
    inner_mod = if sidebar in [nil, ""], do: " pc-layout__main__inner--wide", else: ""

    # No static class on <html>: the colour mode (pc-mode-dark) is added at runtime by pref_init_js.
    # (The old pure-admin `pa-color-*` theme-variant class went away with the theme bundles.)
    html_class = ""

    page_head = page_head_region(rb["pageHead"] || %{}, opts)
    content = content_region(inner, opts[:toc], rb["toc"] || %{})
    footer = if Map.get(regions, "footer", true) != false, do: docset_footer(docset), else: ""
    layout_mod = layout_variant_class(rb["layout"])

    """
    <!doctype html>
    <html lang="en"#{html_class}>
    <head>
      <meta charset="utf-8" />
      <meta name="viewport" content="width=device-width, initial-scale=1" />
      <title>#{esc(title)} · keen-docs</title>
      #{version_control_head(rb["versionControl"])}#{styles(docset)}#{font_head(rb["fonts"])}
      <script>#{pref_init_js()}</script>
    #{docset_head(docset, opts[:canonical])}#{opts[:head] || ""}</head>
    <body class="pc-layout--sticky">
      <nav class="pc-navbar">
        <div class="pc-navbar__inner">
          <div class="pc-navbar__start">
            <button class="pc-navbar__burger burger-menu" type="button" onclick="kdToggleSidebar()" aria-label="Toggle sidebar"><span></span><span></span><span></span></button>
            <div class="kd-brand">#{brand_html(rb, docset)}</div>
            #{if header_cfg(rb)["nav"] == "off", do: "", else: top_nav_html(active_top_code(docset))}
          </div>
          <div class="pc-navbar__center">
            #{search_form(opts, regions)}
          </div>
          <div class="pc-navbar__end">
            #{header_end_html(rb, docset)}
          </div>
        </div>
      </nav>
      #{profile_panel_html()}#{settings_panel_html()}
      <div class="pc-layout#{layout_mod}">
        <div class="pc-layout__inner">
          #{aside}<div class="pc-layout__content">
            <main class="pc-layout__main">
              <div class="pc-layout__main__inner#{inner_mod}">
    #{page_head}#{content}
              </div>
            </main>
          </div>
        </div>
    #{footer}  </div>
      <script src="/vendor/pure-css/pure-css.js"></script>
      <script src="/vendor/pure-css/fit.js"></script>
      <script src="/vendor/pure-css/navbar-dropdown.js"></script>
      <script src="/vendor/pure-css/sidebar-resize.js"></script>
      <script>#{layout_js()}</script>
      <script src="/keendocs/settings-panel.js"></script>
      <script>window.pureCss&&pureCss.components&&pureCss.components.initAll(document);</script>
    #{opts[:footer] || ""}</body>
    </html>
    """
  end

  # The per-request render contract from the active theme (falls back to baseline defaults).
  defp render_block(docset), do: KeenDocs.Themes.render_block(theme_id(docset))

  # The header search box, gated by the theme's `regions.search` ("off" hides it; anything else
  # keeps the default centered position — moving it start/end is deferred).
  defp search_form(opts, regions) do
    if Map.get(regions, "search", "center") == "off" do
      ""
    else
      # pure-css's `.pc-navbar-search` is a click-trigger box (icon · placeholder · kbd), not an
      # input. We keep the native chrome but slot a real submittable <input> where the placeholder
      # span sits — the first place the pure-css contract had to bend (see harness `.pc-navbar-search__input`).
      ~s(<form class="pc-navbar-search pc-navbar-search--md kd-search" action="/search" method="get" role="search">) <>
        ~s(<span class="pc-navbar-search__icon" aria-hidden="true">&#128269;</span>) <>
        ~s(<input class="pc-navbar-search__input" name="q" value="#{esc(opts[:q] || "")}" placeholder="Search docs…" autocomplete="off" aria-label="Search docs" />) <>
        ~s(<span class="pc-navbar-search__shortcut" aria-hidden="true"><kbd>/</kbd></span>) <>
        ~s(</form>)
    end
  end

  # The active header composition block (falls back to the render defaults when a theme omits it).
  defp header_cfg(rb), do: rb["header"] || KeenDocs.Themes.render_defaults()["header"]

  # The pc-navbar__end cluster, composed per the header block: per-doc_set links, the Resolve
  # utility link, an optional primary CTA button, then the dark-mode toggle and profile button.
  # Keeping this budget small is what stops the centred search from being crushed (start/end are
  # both flex-shrink:0 in the pure-css navbar shell).
  defp header_end_html(rb, docset) do
    h = header_cfg(rb)

    [
      if(h["links"] == "off", do: "", else: header_links(docset)),
      if(h["resolve"] == false, do: "", else: ~s(<a class="kd-top-link" href="/resolve">Resolve package.json →</a>)),
      header_cta_html(h["cta"]),
      if(h["modeToggle"] == false, do: "", else: mode_toggle_html()),
      if(h["profile"] == false, do: "", else: profile_btn_html())
    ]
    |> Enum.join()
  end

  # An optional primary call-to-action pinned in the header end (e.g. a GitHub button). Uses
  # keen-docs' own `.kd-btn` so it inherits the active theme's button skin. `icon` is emitted
  # verbatim (emoji or inline SVG from the trusted theme/doc_set config); `label` is escaped.
  defp header_cta_html(%{"url" => url} = cta) when is_binary(url) do
    variant = cta["style"] || "primary"
    icon = if cta["icon"], do: ~s(<span class="kd-btn__icon" aria-hidden="true">#{cta["icon"]}</span>), else: ""
    label = if cta["label"], do: ~s(<span class="kd-cta__label">#{esc(cta["label"])}</span>), else: ""
    ~s(<a class="kd-btn kd-btn--#{esc(variant)} kd-btn--sm kd-cta" href="#{esc(url)}" target="_blank" rel="noopener">#{icon}#{label}</a>)
  end

  defp header_cta_html(_), do: ""

  # The in-content page head, theme-driven. `opts[:page]` is the page-head DATA (title / crumb /
  # subtitle / badges — the doc supplies WHAT); the theme's `pageHead` block decides HOW (hero band
  # on/off, breadcrumbs on/off, badges on/off). `opts[:hero]` (pre-built HTML) is the legacy path,
  # kept for callers that haven't moved to data. Nothing to show → "".
  defp page_head_region(ph, opts) do
    cond do
      opts[:page] && opts[:page] != [] -> render_page_head(opts[:page], ph)
      opts[:hero] && opts[:hero] != "" -> opts[:hero]
      true -> ""
    end
  end

  defp render_page_head(page, ph) do
    crumb = if Map.get(ph, "crumbs", true), do: page[:crumb] || "", else: ""
    badges = if Map.get(ph, "badges", true), do: page[:badges], else: nil

    if Map.get(ph, "hero", true) do
      # Full hero band (the default look).
      page_hero(crumb: crumb, title: page[:title], subtitle: page[:subtitle], badges: badges)
    else
      # Plain head — crumb + heading, no band (a "reading"/minimal theme). Always yields an <h1>.
      sub =
        case page[:subtitle] do
          s when is_binary(s) and s != "" -> ~s(<p class="kd-lead">#{esc(s)}</p>)
          _ -> ""
        end

      ~s(<header class="kd-pagehead kd-pagehead--plain">#{crumb}<h1>#{esc(page[:title] || "")}</h1>#{sub}</header>)
    end
  end

  # Arrange the content region with an optional table of contents, per the theme's `toc` block.
  # Off / no headings → just the content. `inline` → the TOC above the content; `right-rail` → a
  # two-column grid (content + a sticky rail). The TOC comes from the document's own headings.
  defp content_region(inner, toc, cfg) do
    show? = Map.get(cfg, "show", false) == true and is_list(toc) and toc != []
    placement = Map.get(cfg, "placement", "off")

    case {show?, placement} do
      {true, "inline"} -> toc_html(toc, "kd-toc--inline") <> inner
      {true, "right-rail"} -> ~s(<div class="kd-main-cols">#{inner}#{toc_html(toc, "kd-toc--rail")}</div>)
      _ -> inner
    end
  end

  # A TOC list from `[%{level, id, text}]` — links to the heading anchors, indented by depth.
  defp toc_html(toc, mod) do
    items =
      Enum.map_join(toc, "", fn h ->
        ind = if h.level > 2, do: ~s( style="margin-inline-start:#{(h.level - 2) * 1.2}rem"), else: ""
        ~s(<li#{ind}><a href="##{esc(h.id)}">#{esc(h.text)}</a></li>)
      end)

    ~s(<nav class="kd-toc #{mod}" aria-label="On this page"><div class="kd-toc__title">On this page</div><ul>#{items}</ul></nav>)
  end

  # A named layout variant → a `kd-layout--<slug>` hook class on `.pc-layout` ("default"/absent → none).
  defp layout_variant_class(name) when is_binary(name) do
    if name != "" and name != "default" and name =~ ~r/^[a-z][a-z0-9-]*$/, do: " kd-layout--#{name}", else: ""
  end

  defp layout_variant_class(_), do: ""

  # Optional web fonts from the render block: a stylesheet <link> (Google Fonts etc.) plus a
  # :root override of the pure-css font vars every consumer reads (body → --base-font-family, mono →
  # --base-font-family-mono; a heading font is published as --kd-heading-font, applied in harness_css).
  # nil / no keys → "" (the theme/core font stack stands).
  defp font_head(nil), do: ""

  defp font_head(fonts) when is_map(fonts) do
    link =
      case fonts["href"] do
        h when is_binary(h) and h != "" -> ~s(\n  <link rel="stylesheet" href="#{esc(h)}" />)
        _ -> ""
      end

    decls =
      [
        {"--base-font-family", fonts["body"]},
        {"--base-font-family-mono", fonts["mono"]},
        {"--kd-heading-font", fonts["heading"]}
      ]
      |> Enum.map_join("", fn
        {var, v} when is_binary(v) and v != "" -> "#{var}:#{esc(v)};"
        _ -> ""
      end)

    style = if decls == "", do: "", else: ~s(\n  <style>:root{#{decls}}</style>)
    link <> style
  end

  defp font_head(_), do: ""

  # Loads the web-multiselect component (module + style) when a theme renders the version control as
  # one. Use the SAME URL as the doc set's demos so the ES module dedupes (no double custom-element
  # registration). Navigate-on-change is bound in layout_js.
  defp version_control_head(%{"type" => "web-multiselect"} = c) do
    m = if is_binary(c["module"]), do: ~s(\n  <script type="module" src="#{esc(c["module"])}"></script>), else: ""
    s = if is_binary(c["style"]), do: ~s(\n  <link rel="stylesheet" href="#{esc(c["style"])}" />), else: ""
    m <> s
  end

  defp version_control_head(_), do: ""

  # Progressive-enhancement JS over the pure-css navbar shell: the burger toggles a
  # `body.sidebar-visible` overlay on mobile, and crossing the mobile breakpoint back to desktop
  # normalizes that state (so an open mobile overlay never sticks when widened). Backdrop tap
  # (click on the bare body) closes it.
  #
  # The resize signal comes from `pureCss.viewport` via the `viewport:resize` topic — pure-css owns
  # the single throttled resize source, so this must never add a second `window.resize` listener.
  # The breakpoint is read from `pureCss.config.mobileBreakpoint` (itself single-sourced from the
  # `--pc-mobile-breakpoint` CSS var) rather than re-typed as a JS literal. This script is emitted
  # AFTER pure-css.js so `window.pureCss` is already installed; the raw-listener branch is only a
  # no-pure-css safety net (where there is no second listener to conflict with).
  defp layout_js do
    "function kdToggleSidebar(){var b=document.body,x=document.querySelector('.burger-menu');" <>
      "b.classList.toggle('sidebar-visible');if(x)x.classList.toggle('active');}" <>
      "function kdSyncLayout(){var bp=(window.pureCss&&pureCss.config&&pureCss.config.mobileBreakpoint)||768;" <>
      "if(window.innerWidth>bp){document.body.classList.remove('sidebar-visible');" <>
      "var x=document.querySelector('.burger-menu');if(x)x.classList.remove('active');}}" <>
      "if(window.pureCss&&pureCss.events)pureCss.events.on('viewport:resize',kdSyncLayout);" <>
      "else window.addEventListener('resize',kdSyncLayout);" <>
      "document.body.addEventListener('click',function(e){if(document.body.classList.contains('sidebar-visible')&&e.target===document.body)kdToggleSidebar();});" <>
      version_control_js() <>
      profile_js()
  end

  # Navigate when the <web-multiselect> version switcher changes (single-select → selectedValues[0]
  # is the target path). Guarded by a ready flag so the initial preselect sync can't redirect.
  defp version_control_js do
    "var kv=document.querySelector('web-multiselect.kd-version');" <>
      "if(kv){var kvr=false;setTimeout(function(){kvr=true;},700);" <>
      "kv.addEventListener('change',function(e){if(!kvr)return;" <>
      "var vs=e&&e.detail&&e.detail.selectedValues;var v=Array.isArray(vs)?vs[0]:vs;" <>
      "if(v&&v!==location.pathname)location.href=v;});}"
  end

  # Profile panel behaviour (keen-docs' own kd-* panel): the header button toggles `.kd-profile-panel--open`
  # (a slide-in + scroll-lock), the overlay/close button and an outside click dismiss it, and the
  # Profile/Favorites tabs swap `--active` on `[data-profile-tab]`/`[data-profile-panel]`.
  defp profile_js do
    "function kdToggleProfile(){var p=document.getElementById('profilePanel');if(!p)return;" <>
      "var o=p.classList.toggle('kd-profile-panel--open');document.body.classList.toggle('kd-scroll-lock',o);}" <>
      "function kdCloseProfile(){var p=document.getElementById('profilePanel');if(!p)return;" <>
      "p.classList.remove('kd-profile-panel--open');document.body.classList.remove('kd-scroll-lock');}" <>
      "document.addEventListener('click',function(e){var p=document.getElementById('profilePanel')," <>
      "b=document.querySelector('.pc-navbar__profile-btn');if(p&&b&&p.classList.contains('kd-profile-panel--open')" <>
      "&&!p.contains(e.target)&&!b.contains(e.target))kdCloseProfile();});" <>
      "document.querySelectorAll('[data-profile-tab]').forEach(function(t){t.addEventListener('click',function(){" <>
      "var id=t.dataset.profileTab;" <>
      "document.querySelectorAll('[data-profile-tab]').forEach(function(x){x.classList.toggle('kd-tabs__item--active',x.dataset.profileTab===id);});" <>
      "document.querySelectorAll('[data-profile-panel]').forEach(function(x){x.classList.toggle('kd-tabs__panel--active',x.dataset.profilePanel===id);});" <>
      "});});" <>
      "document.querySelectorAll('.kd-profile-panel__favorite-item').forEach(function(i){i.addEventListener('click',function(e){" <>
      "if(e.target.closest('.kd-profile-panel__favorite-remove'))return;if(i.dataset.href)location.href=i.dataset.href;});});" <>
      "document.querySelectorAll('.kd-profile-panel__favorite-remove').forEach(function(b){b.addEventListener('click',function(e){" <>
      "e.stopPropagation();var li=b.closest('li');if(li)li.style.display='none';});});"
  end

  @doc """
  Pre-rendered navigation sidebar: an optional version selector (carries the current slug
  across versions) above the nav tree from `get_doc_nav` (already in render order). Sections
  are group headers; leaves link to their page. A leaf may pin its own `variant_code` (e.g. a
  doc-set-wide 'shared' page) and its URL then honours THAT variant's `show_in_path`, so a
  shared page lands at `/set/slug` while a versioned page keeps its version segment.
  `active_slug` marks the current page. `variants` is the full `list_doc_variants` result.
  """
  def sidebar_html(set, nav_rows, active_variant, active_slug, variants, docset \\ nil) do
    vmap = Map.new(variants, &{&1.code, &1.show_in_path})
    # Un-pinned (versioned) leaves render under the active version — but when you're on a
    # doc-set-wide page (a hidden variant), they fall back to the DEFAULT version, not this
    # page's hidden variant, so they keep their version segment.
    base_variant =
      if Map.get(vmap, active_variant) == true, do: active_variant, else: default_version(variants)

    selector = version_selector(set, variants, active_variant, active_slug, render_block(docset)["versionControl"])

    items =
      Enum.map_join(nav_rows, "", fn n ->
        # Leaves align consistently whether or not they sit under a section header — the header
        # does the grouping, so a level-2 leaf (under a section) must NOT be pushed right of a
        # level-1 ungrouped leaf like "Overview" (that mismatch is what made Overview look odd).
        # Only genuinely deeper nesting (level 3+) gets a small indent.
        ind = if n.level > 2, do: ~s( style="margin-inline-start:#{(n.level - 2) * 0.7}rem"), else: ""

        if n.is_section do
          ~s(<li class="pc-sidebar__section"#{ind}>#{esc(n.label)}</li>)
        else
          v = n.variant_code || base_variant
          show = Map.get(vmap, v, true)
          active = if n.slug == active_slug, do: " pc-sidebar__link--active", else: ""

          ~s(<li class="pc-sidebar__item"#{ind}><a class="pc-sidebar__link#{active}" href="#{doc_path(set, v, n.slug, show)}"><span class="pc-sidebar__label">#{esc(n.label)}</span></a></li>)
        end
      end)

    nav = if items == "", do: "", else: ~s(<nav class="pc-sidebar__nav"><ul>#{items}</ul></nav>)

    # The navbar→sidebar overflow is now handled natively by pure-css's fit.js (it
    # injects a "Browse" section into #kd-nav-overflow, rendered by layout/3). The sidebar just carries
    # the version switcher + this doc set's own nav.
    if selector == "" and nav == "", do: "", else: selector <> nav
  end

  # The default version variant code (a shown-in-path variant): is_default first, else the first.
  defp default_version(variants) do
    versions = Enum.filter(variants, & &1.show_in_path)
    v = Enum.find(versions, & &1.is_default) || List.first(versions)
    v && v.code
  end

  # A version <select> that jumps to the same page under another version, carrying the current
  # slug across. "Versions" are the variants shown in the path (components); a hidden 'shared'
  # variant holding doc-set-wide pages is not a version and is skipped. Plain-page harness → a
  # one-line onchange navigation, no framework.
  defp version_selector(set, variants, active_variant, active_slug, vc) do
    versions = Enum.filter(variants, & &1.show_in_path)
    on_version = Enum.any?(versions, &(&1.code == active_variant))
    # carry the current slug across versions — but only when it IS a versioned page; a
    # doc-set-wide slug has no per-version copy, so switch to that version's Overview instead.
    slug = if on_version, do: active_slug || "index", else: "index"

    if versions == [] do
      ""
    else
      selected = if on_version, do: active_variant, else: default_version(variants)

      opts =
        Enum.map_join(versions, "", fn v ->
          sel = if v.code == selected, do: " selected", else: ""
          ~s(<option value="/#{esc(set)}/#{esc(v.code)}/#{esc(slug)}"#{sel}>#{esc(v.title || v.code)}</option>)
        end)

      case vc do
        %{"type" => "web-multiselect"} = c ->
          # Dogfood: the version switcher IS a <web-multiselect> (single-select). The `label` is the
          # package pill; navigate-on-change is bound in layout_js; the module/style load in the head.
          label = c["label"] || set

          ~s(<div class="kd-version-l kd-version-l--wms"><span class="kd-version-pkg"><span class="kd-version-dot"></span>#{esc(label)}</span>) <>
            ~s(<web-multiselect class="kd-version" multiple="false" placeholder="version">#{opts}</web-multiselect></div>)

        _ ->
          ~s(<label class="kd-version-l d-flex align-items-center gap-2">version<select class="kd-version" onchange="location.href=this.value">#{opts}</select></label>)
      end
    end
  end

  @doc """
  The global (hub) top navigation, shown site-wide. Level-1 nodes render as top-bar items;
  a level-1 section with children becomes a hover dropdown of its level-2 links. Each leaf
  targets a doc_set (→ its homepage), an internal site_page, or an external URL.
  """
  def top_nav_html(active_code \\ nil) do
    case hub_nav() do
      [] ->
        ""

      rows ->
        tops = Enum.filter(rows, &(&1.level == 1))

        items =
          Enum.map_join(tops, "", fn n ->
            kids = Enum.filter(rows, &(&1.level == 2 and String.starts_with?(&1.node_path, n.node_path <> ".")))
            active = top_active?(n, kids, active_code)

            act = if active, do: " pc-navmenu__item--active", else: ""
            # the fit engine no longer auto-pins the active item — pin it ourselves so the current section keeps
            # its bar spot and the rest collapse into the sidebar first (highest priority drops last).
            prio = if active, do: ~s( data-pc-fit-nav-priority="100"), else: ""

            if n.is_section and kids != [] do
              {href, _ext?} = nav_href(n)
              menu = Enum.map_join(kids, "", fn k -> ~s(<li>#{nav_link(k)}</li>) end)

              ~s(<li class="pc-navmenu__item pc-navmenu__item--has-dropdown#{act}"#{prio}>) <>
                ~s(<a class="pc-navmenu__link" href="#{esc(href)}">#{esc(n.label)}</a>) <>
                ~s(<ul class="pc-navmenu__dropdown">#{menu}</ul></li>)
            else
              ~s(<li class="pc-navmenu__item#{act}"#{prio}>#{nav_link(n)}</li>)
            end
          end)

        # pure-css's fit.js: as the header narrows it folds the lowest-priority
        # top-nav items into the sidebar (target #kd-nav-overflow) under a "Browse" .pc-sidebar__section
        # — leaves become links, dropdowns become collapsible groups. The --active item auto-pins.
        ~s(<nav class="pc-navmenu" data-pc-fit-nav="sidebar" data-pc-fit-nav-label="Browse" data-pc-fit-nav-target="#kd-nav-overflow"><ul>#{items}</ul></nav>)
    end
  end

  # Is this top-nav node the one for the current doc_set? A leaf matches its own doc_set_code; a
  # section matches when any of its children targets the active doc_set (e.g. "Components" ← the
  # web-multiselect doc_set lives under it). External/site-page items never light up here.
  defp top_active?(_n, _kids, nil), do: false

  defp top_active?(n, kids, code) do
    n.doc_set_code == code or Enum.any?(kids, &(&1.doc_set_code == code))
  end

  # The active doc_set's code (drives the top-nav active state); nil on the hub/landing.
  defp active_top_code(nil), do: nil
  defp active_top_code(docset), do: Map.get(docset, :code)

  defp hub_nav do
    Content.rows(Content.get_site_nav("hub"))
  rescue
    _ -> []
  end

  # A plain nav anchor — no class; pure-css styles it via `.pc-navmenu > ul > li > a`
  # (top level) and `.pc-navmenu__dropdown li a` (menu items), skinned by the active theme.
  defp nav_link(n) do
    {href, external?} = nav_href(n)
    tgt = if external?, do: ~s( target="_blank" rel="noopener"), else: ""
    ~s(<a href="#{esc(href)}"#{tgt}>#{esc(n.label)}</a>)
  end

  # Resolve a nav node's destination → `{href, external?}` (doc_set landing › slug › url › "#").
  defp nav_href(n) do
    cond do
      n.doc_set_code -> {"/#{n.doc_set_code}", false}
      n.slug -> {"/#{n.slug}", false}
      n.url -> {n.url, true}
      true -> {"#", false}
    end
  end

  # ── per-doc_set chrome (from get_doc_set.settings) ──────────────────────────
  defp settings(%{settings: s}) when is_map(s), do: s
  defp settings(_), do: %{}

  # ── page stylesheets (pure-css only) ────────────────────────────────────────
  # keen-docs is a pure-css-ONLY consumer. The single foundation bundle (@keenmate/pure-css's
  # `pure-css.css`: --base-*/--pc-* vars + reboot + scrollbars + grid + utilities + the pc-* app
  # shell) is linked first as the BASELINE. keen-docs' own layers then inline AFTER it so they win:
  # the dark-mode --base-* override (the bundle is light-only), the per-doc_set accent/vars override,
  # keen-docs' own components (kd-*), the harness chrome-glue, and the rendered content (kd-*).
  # (No-FOUC on mode is handled by pref_init_js, which sets pc-mode-dark on <html> pre-paint.)
  defp styles(docset) do
    pure_css_link() <>
      ~s(  <style>#{dark_theme_css()}#{theme_css(docset)}#{component_css()}#{harness_css()}#{content_css()}</style>)
  end

  defp pure_css_link, do: ~s(  <link rel="stylesheet" href="/vendor/pure-css/pure-css.css" />\n)

  # The active render-contract "theme" for this doc_set — now a NAME only (the CSS theme bundles are
  # gone with the pure-admin dependency). One global default (`config :keen_docs, :theme`), overridable
  # per doc_set via `settings["theme"]["id"]`. Feeds `KeenDocs.Themes.render_block/1` (hero/toc/header
  # composition from keendocs.json) and — via the same `settings["theme"]` map — the accent/vars
  # micro-override (`theme_css/1`). "none"/nil/absent → the baseline render contract.
  defp theme_id(docset) do
    case get_in(settings(docset), ["theme", "id"]) || Application.get_env(:keen_docs, :theme) do
      id when is_binary(id) and id != "none" -> id
      _ -> nil
    end
  end

  # Dark mode: a --base-* override scoped to `html.pc-mode-dark`, inlined so the toggle
  # flips instantly with no flash. Read once at compile time (single source: dark-theme.css).
  @external_resource "priv/web/dark-theme.css"
  @dark_theme_css (case File.read("priv/web/dark-theme.css") do
                     {:ok, css} -> css
                     _ -> ""
                   end)
  defp dark_theme_css, do: @dark_theme_css

  # Applied in <head> before the body paints, so the initial reader preferences are set with no FOUC
  # or reflow flash. Both are class toggles on <html> (so they MUST land pre-paint — restoring them
  # from the end-of-body panel script would repaint/reflow): the colour mode (explicit `kd-mode` wins,
  # else follow the OS `prefers-color-scheme`) and the font-size rem-base class (`.font-size-*`). The
  # settings panel (settings-panel.js) only reflects these into its controls; font-family + the sidebar
  # states, which don't reflow the page, are restored there.
  defp pref_init_js do
    "(function(){try{var d=document.documentElement,m=localStorage.getItem('kd-mode');" <>
      "if(m==='dark'||(!m&&matchMedia('(prefers-color-scheme:dark)').matches))d.classList.add('pc-mode-dark');" <>
      "var f=localStorage.getItem('kd-font-size');" <>
      "if(f&&f!=='default')d.classList.add('font-size-'+f);}catch(e){}})();"
  end

  # Top-bar button that toggles the dark class and persists the choice.
  defp mode_toggle_html do
    onclick =
      "var d=document.documentElement.classList.toggle('pc-mode-dark');" <>
        "try{localStorage.setItem('kd-mode',d?'dark':'light');}catch(e){}"

    ~s(<button type="button" class="kd-mode" onclick="#{onclick}" title="Toggle dark mode" aria-label="Toggle dark mode">◑</button>)
  end

  # The navbar trigger for the profile panel (pure-css's `pc-navbar__profile-btn`).
  defp profile_btn_html do
    # onclick built as a binding (not a literal in the sigil): a paren-delimited ~s() would treat the
    # `()` in `kdToggleProfile()` as nested delimiters. Mirrors mode_toggle_html.
    onclick = "kdToggleProfile()"

    ~s(<button type="button" class="pc-navbar__profile-btn" onclick="#{onclick}" aria-label="Open profile"><span class="kd-btn__icon">&#128100;</span><span class="pc-navbar__profile-name">Guest</span></button>)
  end

  # The slide-in profile panel — keen-docs' own, modeled on pure-admin (header · tabs · Profile nav · Favorites ·
  # fixed footer). Content is docs-flavoured placeholder for now (auth/favorites aren't wired yet);
  # the Favorites tab previews keen-docs' planned per-user favorites.
  defp profile_panel_html do
    """
    <div class="kd-profile-panel" id="profilePanel">
      <div class="kd-profile-panel__overlay" onclick="kdCloseProfile()"></div>
      <div class="kd-profile-panel__content">
        <div class="kd-profile-panel__header">
          <div class="kd-profile-panel__avatar"><span class="kd-profile-panel__avatar-icon">&#128100;</span></div>
          <div class="kd-profile-panel__info">
            <h3 class="kd-profile-panel__name" title="Guest">Guest</h3>
            <p class="kd-profile-panel__email" title="not signed in">not signed in</p>
            <span class="kd-badge">Reader</span>
          </div>
          <button class="kd-profile-panel__close" onclick="kdCloseProfile()" aria-label="Close profile">&#10005;</button>
        </div>
        <div class="kd-profile-panel__tabs">
          <div class="kd-tabs kd-tabs--full">
            <button class="kd-tabs__item kd-tabs__item--active" data-profile-tab="profile" title="Profile"><span class="kd-profile-panel__tab-text">Profile</span></button>
            <button class="kd-tabs__item" data-profile-tab="favorites" title="Favorites"><span class="kd-profile-panel__tab-text">Favorites</span></button>
          </div>
        </div>
        <div class="kd-profile-panel__body">
          <div class="kd-tabs__panel kd-tabs__panel--active" data-profile-panel="profile">
            <nav class="kd-profile-panel__nav"><ul>
              <li><a href="#" class="kd-profile-panel__nav-item"><span class="kd-profile-panel__nav-icon">&#128100;</span>Profile settings</a></li>
              <li><a href="#" class="kd-profile-panel__nav-item"><span class="kd-profile-panel__nav-icon">&#128221;</span>My notes</a></li>
              <li><a href="#" class="kd-profile-panel__nav-item"><span class="kd-profile-panel__nav-icon">&#9881;</span>Preferences</a></li>
              <li><a href="#" class="kd-profile-panel__nav-item"><span class="kd-profile-panel__nav-icon">&#10067;</span>Help &amp; support</a></li>
            </ul></nav>
          </div>
          <div class="kd-tabs__panel" data-profile-panel="favorites">
            <div class="kd-profile-panel__favorites"><ul>
              <li><div class="kd-profile-panel__favorite-item" data-href="/web-multiselect"><span class="kd-profile-panel__favorite-icon">&#11088;</span><span class="kd-profile-panel__favorite-label">Web MultiSelect</span><button class="kd-profile-panel__favorite-remove" title="Remove">&#10005;</button></div></li>
              <li><div class="kd-profile-panel__favorite-item" data-href="/backend-guidelines"><span class="kd-profile-panel__favorite-icon">&#11088;</span><span class="kd-profile-panel__favorite-label">Backend guidelines</span><button class="kd-profile-panel__favorite-remove" title="Remove">&#10005;</button></div></li>
            </ul></div>
            <div class="kd-profile-panel__favorites-add"><button class="kd-btn kd-btn--sm kd-btn--outline-secondary kd-btn--block">+ Add current page</button></div>
          </div>
        </div>
        <div class="kd-profile-panel__footer">
          <button class="kd-btn kd-btn--primary kd-btn--block">Sign in</button>
          <button class="kd-btn kd-btn--danger kd-btn--block">Sign out</button>
        </div>
      </div>
    </div>
    """
  end

  # The floating reader settings panel — keen-docs' own `.kd-settings-panel` offcanvas (a gear tab on
  # the page edge, styled by keendocs-components.css). Its control set is scoped to what
  # keen-docs supports: appearance (light/dark/auto), font size, font family, and the sidebar
  # (docked/hidden + drag-to-resize). settings-panel.js wires the controls and persists to `kd-*`
  # localStorage; mode + font-size are also restored pre-paint by `pref_init_js`. No theme switcher —
  # the theme is server-resolved per doc_set / config (see `styles/1`).
  defp settings_panel_html do
    """
    <div class="kd-settings-panel" id="kdSettingsPanel">
      <button class="kd-settings-panel__toggle" id="kdSettingsToggle" type="button" title="Settings" aria-label="Settings">&#9881;</button>
      <div class="kd-settings-panel__content">
        <h3 class="kd-settings-panel__title">Settings</h3>
        <div class="kd-settings-panel__section">
          <label class="kd-settings-panel__label" for="kdModeSelector">Appearance</label>
          <select class="kd-settings-panel__select" id="kdModeSelector">
            <option value="auto">Auto (system)</option>
            <option value="light">Light</option>
            <option value="dark">Dark</option>
          </select>
        </div>
        <div class="kd-settings-panel__section">
          <label class="kd-settings-panel__label" for="kdFontSizeSelector">Font size</label>
          <select class="kd-settings-panel__select" id="kdFontSizeSelector">
            <option value="small">Small</option>
            <option value="default">Default</option>
            <option value="large">Large</option>
            <option value="xlarge">Extra large</option>
          </select>
          <small class="kd-settings-panel__hint">Rescales the page. All elements scale proportionally.</small>
        </div>
        <div class="kd-settings-panel__section">
          <label class="kd-settings-panel__label" for="kdFontFamilySelector">Font family</label>
          <select class="kd-settings-panel__select" id="kdFontFamilySelector">
            <option value="default">Theme default</option>
            <option value="serif">Serif</option>
            <option value="mono">Monospace</option>
            <option value="manrope">Manrope</option>
            <option value="maven-pro">Maven Pro</option>
            <option value="signika">Signika</option>
          </select>
        </div>
        <div class="kd-settings-panel__section">
          <label class="kd-settings-panel__label" for="kdSidebarBehaviorSelector">Sidebar</label>
          <select class="kd-settings-panel__select" id="kdSidebarBehaviorSelector">
            <option value="normal">Docked</option>
            <option value="hidden">Hidden</option>
          </select>
          <div class="kd-settings-panel__checkbox-group">
            <label class="kd-checkbox">
              <input type="checkbox" id="kdSidebarResizable">
              <span class="kd-checkbox__box"></span>
              <span class="kd-checkbox__label">Resizable (drag the edge)</span>
            </label>
          </div>
        </div>
        <div class="kd-settings-panel__section">
          <button class="kd-btn kd-btn--secondary kd-btn--block" id="kdResetSettings" type="button">Reset to defaults</button>
        </div>
      </div>
    </div>
    """
  end

  # Per-doc_set theme: overrides `--base-*` from `settings.theme`, layered after the defaults so
  # it wins. `accent` sets --base-accent-color and re-derives hover/active/light at runtime via
  # color-mix (the SCSS build derives them, but a live override can't run Sass). `theme.vars` is
  # an escape hatch: any `{"page-bg" => "#…"}` becomes `--base-page-bg: #…`. Because every
  # consumer — the chrome, the kd-* content, and embedded web/svelte components — reads the same
  # variables, this one block re-themes all of them, including a mounted <web-multiselect>.
  defp theme_css(nil), do: ""

  defp theme_css(docset) do
    case theme_decls(settings(docset)["theme"]) do
      "" -> ""
      decls -> ":root{#{decls}}"
    end
  end

  defp theme_decls(theme) when is_map(theme) do
    accent_decls(theme["accent"]) <> var_decls(theme["vars"])
  end

  defp theme_decls(_), do: ""

  defp accent_decls(nil), do: ""

  defp accent_decls(accent) do
    a = esc(to_string(accent))

    # Also publish the raw accent so dark mode (.pc-mode-dark) can brighten it for
    # contrast on dark surfaces while keeping the doc's brand hue (see dark-theme.css).
    "--kd-doc-accent:#{a};" <>
      "--base-accent-color:#{a};" <>
      "--base-accent-color-hover:color-mix(in srgb, #{a} 88%, #fff);" <>
      "--base-accent-color-active:color-mix(in srgb, #{a} 76%, #fff);" <>
      "--base-accent-color-light:color-mix(in srgb, #{a} 8%, transparent);" <>
      "--base-focus-ring-color:#{a};"
  end

  defp var_decls(vars) when is_map(vars) do
    Enum.map_join(vars, "", fn {k, v} ->
      "--base-#{esc(to_string(k))}:#{esc(to_string(v))};"
    end)
  end

  defp var_decls(_), do: ""

  # The navbar brand slot. A theme's render block can supply `brand.logo` (a logo image — e.g. a
  # theme asset like /themes/dhl/assets/dhl-logo.svg) and/or `brand.label` (primary text); the
  # doc_set title still renders as the suffix. No brand block → the plain "keen-docs" wordmark.
  defp brand_html(rb, docset) do
    b = (rb && rb["brand"]) || %{}
    logo = b["logo"]
    label = b["label"]

    suffix = brand_suffix(docset)

    cond do
      is_binary(logo) and logo != "" ->
        # Logo + a stacked wordmark: the theme label on top, the doc_set as a small line beneath
        # (matches the DHL mockup — "DEVELOPER DOCS" over a tiny "/ web-multiselect"), divided from
        # the logo by a left rule. Only render the label block when there's something to show.
        logo_html = ~s(<a class="kd-brand-logo" href="/"><img src="#{esc(logo)}" alt="#{esc(label || "logo")}" /></a>)

        label_html =
          if (label && label != "") or suffix != "",
            do: ~s(<span class="kd-brand-label">#{esc(label || "")}#{suffix}</span>),
            else: ""

        logo_html <> label_html

      true ->
        ~s(<h1><a href="/">#{esc(label || "keen-docs")}</a></h1>) <> suffix
    end
  end

  defp brand_suffix(nil), do: ""

  defp brand_suffix(docset) do
    case docset.title do
      nil -> ""
      t -> ~s(<span class="kd-brand-set">/ #{esc(t)}</span>)
    end
  end

  defp header_links(nil), do: ""

  defp header_links(docset) do
    case settings(docset)["header_links"] do
      links when is_list(links) ->
        Enum.map_join(links, "", fn l ->
          ~s(<a class="kd-top-link" href="#{esc(l["url"])}" target="_blank" rel="noopener">#{esc(l["label"])}</a>)
        end)

      _ ->
        ""
    end
  end

  # The page footer — pure-css's `pc-layout__footer` anatomy (start / center / end sections).
  # `start` carries copyright · author; `center` the footer links; `end` (stacked) the social
  # handles. Always rendered so the shell is complete; falls back to a bare keen-docs line.
  defp docset_footer(docset) do
    s = settings(docset)
    f = s["footer"] || %{}
    copy = f["copyright"]
    author = s["author"]
    site_url = s["site_url"]

    author_html =
      cond do
        author && site_url -> ~s( · <a href="#{esc(site_url)}" target="_blank" rel="noopener">#{esc(author)}</a>)
        author -> ~s( · #{esc(author)})
        true -> ""
      end

    left = "#{esc(copy || "")}#{author_html}"
    left = if left == "", do: "keen-docs", else: left

    links =
      (f["links"] || [])
      |> Enum.map_join("", fn l -> ~s(<a href="#{esc(l["url"])}">#{esc(l["label"])}</a>) end)

    social =
      (s["social"] || [])
      |> Enum.map_join("", fn x ->
        ~s(<a class="kd-social" href="#{esc(x["url"])}" target="_blank" rel="noopener" title="#{esc(x["name"] || "")}">#{esc(x["name"] || x["icon"] || "link")}</a>)
      end)

    ~s(<footer class="pc-layout__footer">) <>
      ~s(<div class="pc-footer__start"><p class="m-0">#{left}</p></div>) <>
      ~s(<div class="pc-footer__center">#{links}</div>) <>
      ~s(<div class="pc-footer__end pc-footer__end--vertical">#{social}</div>) <>
      ~s(</footer>)
  end

  # <head> contributions from the doc_set: author meta, per-page canonical, and the
  # head_assets list (extra_javascript / stylesheets declared once for the whole set).
  defp docset_head(docset, canonical) do
    s = settings(docset)
    author = if a = s["author"], do: ~s(  <meta name="author" content="#{esc(a)}" />\n), else: ""
    canon = if canonical, do: ~s(  <link rel="canonical" href="#{esc(canonical)}" />\n), else: ""
    author <> canon <> head_assets(s["head_assets"])
  end

  defp head_assets(list) when is_list(list), do: Enum.map_join(list, "", &head_asset/1)
  defp head_assets(_), do: ""

  # A string asset is classified by extension; an object carries its own rel/type.
  defp head_asset(a) when is_binary(a) do
    cond do
      String.ends_with?(a, ".css") -> ~s(  <link rel="stylesheet" href="#{esc(a)}" />\n)
      String.ends_with?(a, ".js") or String.ends_with?(a, ".mjs") -> ~s(  <script type="module" src="#{esc(a)}"></script>\n)
      true -> ~s(  <link href="#{esc(a)}" />\n)
    end
  end

  defp head_asset(%{"src" => src} = a),
    do: ~s(  <script src="#{esc(src)}"#{if a["type"], do: ~s( type="#{esc(a["type"])}"), else: ""}></script>\n)

  defp head_asset(%{"href" => href} = a),
    do: ~s(  <link rel="#{esc(a["rel"] || "stylesheet")}" href="#{esc(href)}" />\n)

  defp head_asset(_), do: ""

  @doc "A homepage hero band: the doc_set title + its description as a tagline subtitle."
  def hero_html(_title, nil), do: ""
  def hero_html(_title, ""), do: ""

  def hero_html(title, description) do
    ~s(<header class="kd-hero border-bottom"><h1>#{esc(title || "")}</h1><p class="kd-hero-sub">#{esc(description)}</p></header>)
  end

  @doc """
  A full-width page hero band, rendered by `layout/3` above the shell (so it spans the
  sidebar too). `opts`: `:crumb` (pre-built breadcrumb HTML), `:title`, `:subtitle`, `:badges`
  (pre-built HTML). Only `:title` is required; the rest are omitted when blank.
  """
  def page_hero(opts) do
    crumb = opts[:crumb] || ""

    sub =
      case opts[:subtitle] do
        s when is_binary(s) and s != "" -> ~s(<p class="kd-lead">#{esc(s)}</p>)
        _ -> ""
      end

    badges =
      case opts[:badges] do
        b when is_binary(b) and b != "" -> ~s(<div class="kd-pagehead__badges">#{b}</div>)
        _ -> ""
      end

    ~s(<header class="kd-pagehead">#{crumb}<div class="kd-pagehead__row"><h1>#{esc(opts[:title] || "")}</h1>#{badges}</div>#{sub}</header>)
  end

  @doc "A little pill/badge."
  def badge(text, class \\ ""), do: ~s(<span class="kd-badge #{class}">#{esc(text)}</span>)

  # Docs-specific styling layered over pure-css's default shell chrome. The pc-navbar / pc-layout /
  # pc-sidebar / pc-footer STRUCTURE *and look* come from the vendored pure-css.css bundle (+ its baked
  # --pc-* palette); the harness only styles the keen-docs pieces that live inside that shell — the
  # on-bar controls, the content column, the in-content page head, the docs sidebar extras, and the
  # rendered content classes — all via --pc-*/--base-* so they follow the (themeable) header/surface.
  defp harness_css do
    """
    /* box-sizing, body font/colour/margin and the typography reset come from the vendored
       reboot.css; the harness only overrides the page background (docs want the subtle --base-page-bg
       behind cards, not reboot's --pc-main-bg surface) and the link treatment. */
    body{background:var(--base-page-bg,#f6f8fb)}
    a{color:var(--base-accent-color,#2563eb);text-decoration:none} a:hover{text-decoration:underline}
    /* ---- on-bar controls (the bar itself is pure-css default: --pc-navbar-bg) ---- */
    .kd-brand{display:flex;align-items:center}
    .kd-brand h1{font-size:1.68rem;margin:0;font-weight:700}
    .kd-brand a{color:var(--pc-navbar-text,#0f172a)!important;text-decoration:none}
    .kd-brand-logo{display:inline-flex;align-items:center}
    .kd-brand-logo img{height:2.8rem;width:auto;display:block}
    /* stacked wordmark: theme label on top, doc_set as a small line beneath, a left rule dividing it
       from the logo. Sizes tunable via --pc-brand-* (defaults match the DHL mockup: 12px / 10px). */
    .kd-brand-label{display:flex;flex-direction:column;justify-content:center;white-space:nowrap;margin-left:1rem;padding-left:1.1rem;border-left:2px solid var(--pc-brand-divider,var(--pc-border-color,rgba(0,0,0,.18)));font-family:var(--kd-heading-font,inherit);font-weight:800;font-size:var(--pc-brand-label-size,1.2rem);letter-spacing:.12em;line-height:1.18;text-transform:uppercase;color:var(--pc-navbar-text,#0f172a)}
    .kd-brand-set{display:block;font-weight:600;font-size:var(--pc-brand-set-size,1rem);letter-spacing:.14em;text-transform:uppercase;color:var(--pc-navbar-text-secondary,#64748b)}
    .pc-navbar__burger{display:none} @media(max-width:768px){.pc-navbar__burger{display:flex}}
    /* Top nav + search now use pure-css's OWN shell components (pc-navmenu > ul > li > a with
       pc-navmenu__dropdown; pc-navbar-search). The harness only adds the dropdown caret and bends
       the search trigger to carry a real submittable input where its placeholder span would sit. */
    /* dropdown caret drawn as a pseudo-element (NOT text) so fit.js's labelOf() doesn't
       copy it into the rebuilt sidebar label — otherwise the folded item shows our ▾ AND the sidebar
       toggle's own chevron (double marker). */
    .pc-navmenu > ul > li.pc-navmenu__item--has-dropdown > a::after{content:"▾";font-size:.85em;opacity:.6;margin-inline-start:.4rem}
    /* active top-nav item + the fit-nav "Browse" section come from pure-css:
       .pc-navmenu__item--active (currentColor pill) and .pc-sidebar__section. */
    /* on-bar utility text links in pc-navbar__end (Resolve, per-doc_set header_links) — styled like
       the native nav links so the whole bar reads consistently. */
    .kd-top-link{color:var(--pc-navbar-text-secondary,#475569);font-size:1.44rem;padding:0.64rem 1.04rem;border-radius:6px;white-space:nowrap}
    .kd-top-link:hover{background:var(--pc-accent-hover,#eef2ff);color:var(--pc-accent,#2563eb);text-decoration:none}
    /* Reserve the search's min-width on the CENTER FLEX ITEM, not just the input. Flexbox only honours
       a flex item's OWN min-width when distributing space; a min-width on the search (center's child)
       lets center grow to a sliver and the search overflows it onto start/end. Putting 18rem on center
       forces flex to shrink `start` to make room, which shrinks the nav's slot — so fit.js
       finally sees the deficit and folds items into the sidebar (search wins space, nav yields). Below
       the ≤560 hide, center is display:none so this floor never causes overlap. */
    .pc-navbar__center:has(.kd-search){min-width:18rem}
    .pc-navbar-search.kd-search{width:100%;min-width:0;max-width:41.6rem;margin:0 auto;cursor:text}
    .kd-cta{text-decoration:none;white-space:nowrap}
    .pc-navbar-search__input{flex:1;min-width:0;border:0;background:transparent;font:inherit;font-size:1.4rem;color:var(--pc-text-color-1,#1a2233);outline:none}
    .pc-navbar-search__input::placeholder{color:var(--pc-text-color-2,#64748b)}
    .kd-form button{padding:0.64rem 1.28rem;border-radius:6px;border:0;background:var(--pc-accent,#2563eb);color:#fff;cursor:pointer}
    /* Responsive shedding of the NON-nav on-bar controls (fit.js owns the top-nav itself,
       folding it into the sidebar). Order is the point: utility links → CTA label → search + suffix. */
    @media(max-width:1200px){.kd-top-link{display:none}}
    /* The stacked brand wordmark is ~190px wide and won't shrink (nowrap); below tablet it stops the
       the fit engine from freeing enough room (start can't shrink past brand+items, so it overflows
       onto the centred search instead of folding more items). Shed the text label to the logo alone so
       the collapse — and the search — get their space back. */
    @media(max-width:1150px){.kd-brand-label{display:none}}
    @media(max-width:768px){.kd-cta__label{display:none}}
    @media(max-width:560px){.pc-navbar__center{display:none}.kd-brand-set{display:none}}
    .kd-mode{background:transparent;color:var(--pc-navbar-text,#334155);border:1px solid var(--pc-border-color,#cbd5e1);border-radius:6px;padding:0.48rem 0.88rem;font-size:1.6rem;line-height:1;cursor:pointer}
    .kd-mode:hover{background:var(--pc-accent-hover,#eef2f7)}
    .pc-navbar__profile-btn{display:inline-flex;align-items:center;gap:.8rem;background:transparent;border:1px solid var(--pc-border-color,#cbd5e1);color:var(--pc-navbar-text,#334155);border-radius:6px;padding:.5rem 1rem;cursor:pointer;font:inherit;font-size:1.44rem}
    .pc-navbar__profile-btn:hover{background:var(--pc-accent-hover,#eef2f7)}
    .pc-navbar__profile-name{font-weight:600}
    /* ---- content column + in-content page head ---- */
    .pc-layout__main__inner{max-width:102.4rem;margin:0 auto;padding:2.8rem 3.2rem}
    .pc-layout__main__inner--wide{max-width:134.4rem}
    .kd-pagehead{margin:0 0 2.4rem}
    .kd-pagehead__row{display:flex;align-items:center;gap:1.12rem;flex-wrap:wrap}
    .kd-pagehead h1{margin:0.16rem 0;font-size:2.8rem;line-height:1.15;font-family:var(--kd-heading-font,inherit)}
    .kd-pagehead--plain{padding-bottom:0.8rem;border-bottom:1px solid var(--base-border-color,#e5e9f0)}
    .kd-lead{margin:0.8rem 0 0;color:var(--base-text-color-2,#64748b);font-size:1.632rem;max-width:76.8rem}
    .kd-pagehead__badges{display:flex;gap:0.64rem;flex-wrap:wrap}
    .kd-crumb{font-size:1.312rem;color:var(--base-text-color-2,#64748b);margin-bottom:0.88rem}
    .kd-crumb a{color:var(--base-text-color-2,#64748b)} .kd-crumb a:hover{color:var(--base-accent-color,#2563eb)}
    h1{font-size:2.56rem;margin:0.32rem 0 1.6rem;font-family:var(--kd-heading-font,inherit)} h2{font-size:1.92rem;margin:2.72rem 0 0.96rem;font-family:var(--kd-heading-font,inherit)}
    /* ---- table of contents (theme-driven placement) ---- */
    .kd-main-cols{display:grid;grid-template-columns:minmax(0,1fr) 24rem;gap:3.2rem;align-items:start}
    @media(max-width:1100px){.kd-main-cols{grid-template-columns:1fr}.kd-toc--rail{display:none}}
    .kd-toc__title{font-size:1.12rem;text-transform:uppercase;letter-spacing:.05em;color:var(--base-text-color-3,#94a3b8);font-weight:700;margin-bottom:0.64rem}
    .kd-toc ul{list-style:none;margin:0;padding:0}
    .kd-toc li{margin:0.32rem 0} .kd-toc a{color:var(--base-text-color-2,#64748b);font-size:1.36rem} .kd-toc a:hover{color:var(--base-accent-color,#2563eb)}
    .kd-toc--rail{position:sticky;top:6.4rem;border-inline-start:1px solid var(--base-border-color,#e5e9f0);padding-inline-start:1.6rem}
    .kd-toc--inline{background:var(--base-main-bg,#fff);border:1px solid var(--base-border-color,#e5e9f0);border-radius:8px;padding:1.28rem 1.6rem;margin:0 0 2rem}
    /* ---- docs sidebar: layout METRICS as --pc-sidebar- tokens ----
       pure-css hardcodes sidebar spacing as literals; the harness re-expresses it via variables whose
       defaults live in the var() fallbacks, so a theme tunes LAYOUT declaratively (set e.g.
       --pc-sidebar-padding in its :root) instead of overriding selectors. Colours and fonts still ride
       the --pc- and --base- palette. Spacing-token prototype — see docs/theme-stress-test-dhl.md ---- */
    /* Full height + internal scroll come from the sticky app-shell (body.pc-layout--sticky in core):
       the aside is a stretched flex child spanning header→footer and scrolls its own overflow. The
       harness only (a) sets width to the resizable var so it beats core's 16rem tablet reduction —
       sidebar-resize.js rewrites --pc-local-sidebar-width live; core's ≤768 auto-hide has higher
       specificity and still wins — and (b) pads the scroll pane. Do NOT re-add position/align-self/
       max-height here: those re-break the full-height stretch. */
    .pc-layout__sidebar{width:var(--pc-local-sidebar-width);padding:var(--pc-sidebar-padding,1.8rem 1.4rem 3rem)}
    .pc-sidebar__nav{padding:var(--pc-sidebar-nav-padding,0)}
    .pc-sidebar__nav li{margin:var(--pc-sidebar-item-gap,0.1rem) 0}
    .pc-sidebar__link,.pc-sidebar__toggle{padding:var(--pc-sidebar-link-padding,0.6rem 1.1rem);font-size:var(--pc-sidebar-link-font-size,1.4rem)}
    .pc-sidebar__link .pc-sidebar__label{font-size:var(--pc-sidebar-link-font-size,1.4rem)}
    /* section headings are native .pc-sidebar__section — pure-css owns their spacing/type */
    .kd-version-l{display:flex;align-items:center;gap:0.8rem;font-size:1.088rem;text-transform:uppercase;letter-spacing:.05em;color:var(--base-text-color-3,#94a3b8);font-weight:700;margin:0 0 1.2rem}
    .kd-version{flex:1;padding:0.56rem 0.8rem;border:1px solid var(--base-border-color,#cbd5e1);border-radius:6px;background:var(--base-main-bg,#fff);font-size:1.36rem;color:var(--base-text-color-1,#1a2233);cursor:pointer}
    /* web-multiselect version control (a theme opts in via render-block versionControl) — a package pill wrapping the live component */
    .kd-version-l--wms{display:flex;flex-direction:column;align-items:stretch;gap:0.7rem;margin:0 0 1.8rem;padding:1rem 1.2rem;border:1px solid var(--base-border-color,#e5e9f0);background:var(--base-subtle-bg,#eef1f5);border-radius:10px;text-transform:none;letter-spacing:normal}
    .kd-version-pkg{display:flex;align-items:center;gap:0.7rem;font-family:var(--kd-heading-font,inherit);font-weight:700;font-size:1.24rem;color:var(--base-text-color-1,#1a2233);line-height:1.2;word-break:break-word}
    /* uses --pc-accent (chrome token), not --base-accent-color: the web-multiselect component writes
       --base-* onto :root when it upgrades (its fallback), which would otherwise tint this dot. */
    .kd-version-dot{width:0.8rem;height:0.8rem;border-radius:50%;background:var(--pc-accent,var(--base-accent-color,#2563eb));box-shadow:0 0 0 3px var(--pc-accent-hover,rgba(37,99,235,.12));flex:0 0 auto}
    web-multiselect.kd-version{display:block;width:100%;font-size:1.3rem}
    /* navbar→sidebar overflow (fit.js injects into #kd-nav-overflow): the empty target
       host self-hides, and a sidebar holding nothing but the empty host self-hides too — so the hub
       reads full-width until items actually fold in. :has() is fine (Chrome-target harness). */
    .kd-nav-overflow-host:not(:has(li)){display:none}
    /* space below the folded-in "Browse" block so it isn't crammed against the version pill */
    .kd-nav-overflow-host:has(li){margin-bottom:1.6rem}
    .kd-sidebar:not(:has(.pc-sidebar__item)):not(:has(.pc-sidebar__section)){display:none}
    /* ---- footer link colours (structure/look from pure-css) ---- */
    .pc-layout__footer a{color:var(--base-accent-color,#2563eb)} .kd-social{margin-inline-end:0.96rem}
    /* ---- rendered content ---- */
    .kd-card{background:var(--base-main-bg,#fff);border:1px solid var(--base-border-color,#e5e9f0);border-radius:10px;padding:1.6rem 1.92rem;margin:1.28rem 0}
    .kd-badge{display:inline-block;font-size:1.152rem;padding:0.16rem 0.8rem;border-radius:999px;background:#e2e8f0;color:#334155;font-weight:600}
    .kd-badge.component{background:#dbeafe;color:#1d4ed8} .kd-badge.infrastructure{background:#dcfce7;color:#15803d}
    .kd-badge.guide{background:#fef9c3;color:#854d0e} .kd-badge.rc{background:#fee2e2;color:#b91c1c}
    .kd-badge.default{background:#e0e7ff;color:#4338ca} .kd-badge.hidden{background:#f1f5f9;color:#64748b}
    table{border-collapse:collapse;width:100%} td,th{padding:0.72rem 0.96rem;text-align:left;border-bottom:1px solid var(--base-border-color,#eef1f6)}
    th{font-size:1.248rem;text-transform:uppercase;letter-spacing:.03em;color:var(--base-text-color-2,#64748b)}
    code{background:var(--base-subtle-bg,#eef1f6);padding:0.08rem 0.56rem;border-radius:4px;font-size:.9em}
    .kd-variant{border-left:3px solid var(--base-border-color,#cbd5e1);padding-left:1.44rem;margin:1.6rem 0}
    .kd-docs li{margin:0.24rem 0} .muted{color:var(--base-text-color-2,#64748b)} .kd-desc{font-size:1.312rem;margin-top:0.24rem}
    .kd-form textarea{width:100%;min-height:19.2rem;font-family:var(--base-font-family-mono,ui-monospace,monospace);font-size:1.36rem;padding:1.12rem;border-radius:8px;border:1px solid var(--base-border-color,#cbd5e1)}
    .kd-hit{padding:0.8rem 0;border-bottom:1px solid var(--base-border-color,#eef1f6)}
    .kd-index{margin:3.2rem 0 0;border:1px dashed var(--base-border-color,#cbd5e1);border-radius:8px;padding:0.96rem 1.6rem;background:var(--base-main-bg,#fff)}
    .kd-index summary{cursor:pointer;font-weight:600;color:var(--base-text-color-1,#334155)}
    .kd-index h3{font-size:1.152rem;text-transform:uppercase;letter-spacing:.03em;color:var(--base-text-color-2,#64748b);margin:1.6rem 0 0.48rem}
    .kd-index pre{white-space:pre-wrap;background:var(--base-page-bg,#f8fafc);border:1px solid var(--base-border-color,#eef1f6);border-radius:6px;padding:0.96rem 1.28rem;font-size:1.28rem;margin:0}
    """
  end

  # The engine emits kd-* classes; reuse the POC stylesheet so rendered doc bodies look right.
  defp content_css do
    case File.read("priv/web/keendocs.css") do
      {:ok, css} -> css
      _ -> ""
    end
  end

  # keen-docs-OWNED chrome components (buttons, checkbox, badge, profile panel, settings panel, tabs).
  # Since keen-docs dropped its pure-admin dependency, these are our own `kd-*` copies — styled on
  # pure-css base tokens (--pc-*/--base-*), scoped to what keen-docs actually uses, and free to evolve.
  defp component_css do
    case File.read("priv/web/keendocs-components.css") do
      {:ok, css} -> css
      _ -> ""
    end
  end

  @doc "Body HTML for rendered doc content."
  def body_html(%Output{} = o), do: Output.body_html(o)
  def head_html(%Output{} = o), do: Output.head_html(o)
  def footer_html(%Output{} = o), do: Output.footer_html(o)
end
