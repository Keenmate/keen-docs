defmodule KeenDocs.Web.Router do
  @moduledoc """
  The test-harness routes over the `public.*` content functions:

      GET  /                       hub — every doc_set
      GET  /search?q=&kind=        full-text + trigram search
      GET  /resolve                paste a package.json → doc links
      POST /resolve
      GET  /:set                   set landing — variants + their pages
      GET  /:set/:seg              guide page (hidden variant) OR variant landing
      GET  /:set/:variant/:slug    a rendered document

  Handlers are thin: they call `KeenDocs.Content` (the db-gen wrappers) and render with
  `KeenDocs.Web.View`. Nothing here knows the shape of a component vs a guide — that all
  comes from the data (`kind_code`, `show_in_path`, `applies_to`).
  """
  use Plug.Router
  alias KeenDocs.Content
  alias KeenDocs.Web.View
  import View, only: [esc: 1, badge: 2, doc_path: 4]

  plug Plug.Parsers, parsers: [:urlencoded, :json], pass: ["*/*"], json_decoder: Jason
  plug :match
  plug :dispatch

  # ── island runtime + bundles ──────────────────────────────────────────────
  # A `:::app` island mounts on this plain (non-LiveView) page via keen-phoenix-svelte's
  # `mountStatic()`. Both are served as `text/javascript` so the browser accepts them as
  # ES modules — the App extension points `runtime` at /apps_runtime.js, and each island's
  # bundle resolves under /apps/<name>/main.mjs (the #keen-apps manifest the page emits).
  get "/apps_runtime.js" do
    send_js(conn, "apps_runtime.js")
  end

  get "/apps/:name/main.mjs" do
    send_js(conn, Path.join(["apps", name, "main.mjs"]))
  end

  # ── vendored foundation (@keenmate/pure-css) — the ONLY UI dependency ──────
  # base.css is inlined into the page <style> (FOUC-free --base-*); pure-css.css (the full bundle:
  # vars + reboot + scrollbars + grid + utilities + the pc-* app shell) is linked from here, and the
  # dependency-free JS runtime (pure-css.js / fit.js / navbar-dropdown.js / sidebar-resize.js) is
  # served as text/javascript. Content-type by extension. Declared before the greedy /:set/... routes
  # so /vendor/... isn't read as a document.
  get "/vendor/pure-css/:file" do
    rel = Path.join(["vendor", "pure-css", file])
    if String.ends_with?(file, ".js"), do: send_js(conn, rel), else: send_css(conn, rel)
  end

  # keen-docs' own front-end enhancements (not vendored from pure-admin): the reader settings panel
  # driver. Served as a real ES-flavoured module; declared before the greedy /:set/... routes.
  get "/keendocs/:file" do
    send_js(conn, Path.join(["keendocs", file]))
  end

  # ── hub ───────────────────────────────────────────────────────────────────
  # The hub renders its authored homepage (the 'hub' site's home_slug page); if none is set,
  # it falls back to the auto-generated doc_set table.
  get "/" do
    site = Content.one(Content.get_site("hub"))

    if site && site.home_slug && Content.one(Content.get_site_page("hub", site.home_slug)) do
      render_site_page(conn, site.home_slug, hero: true)
    else
      hub_index_table(conn)
    end
  end

  defp hub_index_table(conn) do
    sets = Content.rows(Content.list_doc_sets())

    rows =
      Enum.map_join(sets, "", fn s ->
        pkg = if s.package_name, do: ~s(<code>#{esc(s.ecosystem_code)}: #{esc(s.package_name)}</code>), else: ~s(<span class="muted">—</span>)

        """
        <tr>
          <td><a href="/#{esc(s.code)}"><strong>#{esc(s.code)}</strong></a></td>
          <td>#{badge(s.kind_code, s.kind_code)}</td>
          <td>#{esc(s.title || "")}#{if s.description, do: ~s(<div class="muted kd-desc">#{esc(s.description)}</div>), else: ""}</td>
          <td>#{pkg}</td>
        </tr>
        """
      end)

    inner = """
    <h1>Documented subjects</h1>
    <div class="kd-card"><table>
      <tr><th>doc_set</th><th>kind</th><th>title</th><th>package</th></tr>
      #{rows}
    </table></div>
    """

    html(conn, View.layout("Home", inner))
  end

  # Render a global standalone page (a hub site_page) — no doc_set sidebar; the global
  # top-nav is its navigation. `opts[:hero]` shows the site title + description band.
  defp render_site_page(conn, slug, opts \\ []) do
    case Content.one(Content.get_site_page("hub", slug)) do
      nil ->
        not_found(conn)

      page ->
        site = Content.one(Content.get_site("hub"))
        output = View.render_markdown(page.content)
        # Page-head DATA (the theme decides whether/how to render it); the hub hero is title + tagline.
        head_data = if opts[:hero] && site, do: [title: site.title, subtitle: site.description], else: nil

        inner = ~s(<article class="kd-page">#{View.body_html(output)}</article>)

        html(conn, View.layout(page.title || slug, inner,
          head: View.head_html(output),
          footer: View.footer_html(output),
          docset: site,
          page: head_data,
          toc: output.toc,
          canonical: canonical_url(site, conn)))
    end
  end

  # ── search ────────────────────────────────────────────────────────────────
  get "/search" do
    conn = fetch_query_params(conn)
    q = conn.query_params["q"]
    kind = conn.query_params["kind"]

    criteria =
      %{}
      |> maybe_put("text", q)
      |> maybe_put("kind", kind)

    hits = Content.rows(Content.search_documents("web", criteria, %{"page_size" => 50}, 1))

    body =
      case hits do
        [] ->
          ~s(<p class="muted">No matches.</p>)

        hits ->
          Enum.map_join(hits, "", fn h ->
            """
            <div class="kd-hit">
              <a href="/#{esc(h.doc_set_code)}/#{esc(h.variant_code)}/#{esc(h.slug)}">#{esc(h.title || h.slug)}</a>
              #{badge(h.kind_code, h.kind_code)}
              <span class="muted"> #{esc(h.doc_set_code)}/#{esc(h.variant_code)} · rank #{Float.round(h.rank, 3)}</span>
            </div>
            """
          end)
      end

    inner = ~s|<h1>Search</h1><p class="muted">query: <code>#{esc(inspect(criteria))}</code> → #{length(hits)} hits</p>#{body}|
    html(conn, View.layout("Search", inner, q: q))
  end

  # ── package.json resolver ─────────────────────────────────────────────────
  get "/resolve" do
    html(conn, View.layout("Resolve", resolve_form(sample_package_json(), nil)))
  end

  post "/resolve" do
    text = conn.body_params["package_json"] || ""
    result =
      case Jason.decode(text) do
        {:ok, json} -> resolve_deps(json)
        {:error, _} -> :bad_json
      end

    html(conn, View.layout("Resolve", resolve_form(text, result)))
  end

  # ── a rendered document (explicit variant) ────────────────────────────────
  get "/:set/:variant/:slug" do
    render_document(conn, set, variant, slug)
  end

  # ── /:set/:seg — guide page (hidden variant) OR a variant landing ──────────
  get "/:set/:seg" do
    variants = Content.rows(Content.list_doc_variants(set))

    cond do
      variants == [] ->
        not_found(conn)

      Enum.any?(variants, &(&1.code == seg)) ->
        variant = Enum.find(variants, &(&1.code == seg))
        variant_landing(conn, set, variant)

      true ->
        # not a variant code → a slug. Resolve it in the default variant (guide page), then
        # in a hidden variant (a doc-set-wide page like /web-multiselect/changelog).
        case resolve_page_variant(set, seg, variants) do
          nil -> not_found(conn)
          vcode -> render_document(conn, set, vcode, seg)
        end
    end
  end

  # ── set landing / homepage ────────────────────────────────────────────────
  # If the set declares a home_slug (its authored landing page), render that document;
  # otherwise fall back to the auto-generated variant list.
  get "/:set" do
    variants = Content.rows(Content.list_doc_variants(set))
    docset = Content.one(Content.get_doc_set(set))
    default = Enum.find(variants, & &1.is_default) || List.first(variants)

    cond do
      # not a doc_set → maybe a global standalone page (a hub site_page like /about)
      variants == [] ->
        if Content.one(Content.get_site_page("hub", set)),
          do: render_site_page(conn, set),
          else: not_found(conn)

      docset && docset.home_slug && default &&
          Content.one(Content.get_document(set, default.code, docset.home_slug)) ->
        render_document(conn, set, default.code, docset.home_slug, hero: true)

      true ->
        set_landing(conn, set, variants)
    end
  end

  match _ do
    not_found(conn)
  end

  # ── rendering ─────────────────────────────────────────────────────────────

  defp set_landing(conn, set, variants) do
    docs = Content.rows(Content.search_documents("web", %{"doc_set" => set}, %{"page_size" => 200, "order_by" => "slug", "order_dir" => "asc"}, 1))

    blocks =
      Enum.map_join(variants, "", fn v ->
        tag =
          cond do
            v.maturity_code && v.maturity_code != "stable" -> badge(v.maturity_code, v.maturity_code)
            v.is_default -> badge("default", "default")
            true -> ""
          end

        hidden = unless v.show_in_path, do: badge("URL segment hidden", "hidden"), else: ""

        items =
          docs
          |> Enum.filter(&(&1.variant_code == v.code))
          |> Enum.map_join("", fn d ->
            ~s(<li><a href="#{doc_path(set, v.code, d.slug, v.show_in_path)}">#{esc(d.title || d.slug)}</a> <span class="muted">#{esc(d.slug)}</span></li>)
          end)

        applies = if v.applies_to, do: ~s(<div class="muted">applies to: <code>#{esc(Jason.encode!(v.applies_to))}</code></div>), else: ""

        """
        <div class="kd-variant">
          <h2>#{esc(v.title || v.code)} <span class="muted">code=#{esc(v.code)}</span> #{tag} #{hidden}</h2>
          #{applies}
          <ul class="kd-docs">#{items}</ul>
        </div>
        """
      end)

    inner = ~s(<div class="kd-crumb"><a href="/">home</a> / #{esc(set)}</div><h1>#{esc(set)}</h1>#{blocks})
    default = Enum.find(variants, & &1.is_default) || List.first(variants)
    {docset, sidebar} = set_chrome(set, default && default.code, nil)
    html(conn, View.layout(set, inner, docset: docset, sidebar: sidebar))
  end

  # The per-set chrome: the doc_set presentation row + the navigation sidebar rendered for
  # the active variant (a single get_doc_nav select, already in render order). `active_slug`
  # marks the current page in the sidebar.
  defp set_chrome(set, active_variant, active_slug) do
    docset = Content.one(Content.get_doc_set(set))
    nav = Content.rows(Content.get_doc_nav(set))
    variants = Content.rows(Content.list_doc_variants(set))
    sidebar = View.sidebar_html(set, nav, active_variant, active_slug, variants, docset)
    {docset, sidebar}
  end

  # Which variant holds a bare `/:set/:slug` page: prefer the default variant, then any hidden
  # (show_in_path=false) variant — doc-set-wide pages (changelog, migration) live in one.
  defp resolve_page_variant(set, slug, variants) do
    default = Enum.find(variants, & &1.is_default) || List.first(variants)

    [default | Enum.filter(variants, &(&1 && not &1.show_in_path))]
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq_by(& &1.code)
    |> Enum.find_value(fn v ->
      if Content.one(Content.get_document(set, v.code, slug)), do: v.code
    end)
  end

  defp variant_landing(conn, set, variant) do
    docs = Content.rows(Content.search_documents("web", %{"doc_set" => set}, %{"page_size" => 200, "order_by" => "slug", "order_dir" => "asc"}, 1))

    items =
      docs
      |> Enum.filter(&(&1.variant_code == variant.code))
      |> Enum.map_join("", fn d ->
        ~s(<li><a href="#{doc_path(set, variant.code, d.slug, variant.show_in_path)}">#{esc(d.title || d.slug)}</a></li>)
      end)

    inner = """
    <div class="kd-crumb"><a href="/">home</a> / <a href="/#{esc(set)}">#{esc(set)}</a> / #{esc(variant.code)}</div>
    <h1>#{esc(variant.title || variant.code)}</h1>
    <ul class="kd-docs">#{items}</ul>
    """

    html(conn, View.layout("#{set} · #{variant.code}", inner))
  end

  defp render_document(conn, set, variant, slug, opts \\ []) do
    case Content.one(Content.get_document(set, variant, slug)) do
      nil ->
        not_found(conn)

      doc ->
        output = View.render_markdown(doc.content)
        index = Content.one(Content.get_document_index(set, variant, slug))
        {docset, sidebar} = set_chrome(set, variant, slug)

        head_data =
          if opts[:hero] && docset do
            # set homepage → the doc_set's own hero (title + description)
            [title: docset.title, subtitle: docset.description]
          else
            crumb = ~s(<div class="kd-crumb"><a href="/">home</a> / <a href="/#{esc(set)}">#{esc(set)}</a> / #{esc(variant)} / #{esc(slug)}</div>)
            [crumb: crumb, title: doc.title || slug, subtitle: frontmatter_desc(doc), badges: doc_badges(docset, variant)]
          end

        inner = ~s(<article class="kd-page">#{View.body_html(output)}</article>\n#{index_panel(index)})

        html(conn, View.layout(doc.title || slug, inner,
          head: View.head_html(output),
          footer: View.footer_html(output),
          docset: docset,
          sidebar: sidebar,
          page: head_data,
          toc: output.toc,
          canonical: canonical_url(docset, conn)))
    end
  end

  # A document's front-matter description → hero subtitle (nil when absent).
  defp frontmatter_desc(%{frontmatter: fm}) when is_map(fm), do: fm["description"] || fm["summary"]
  defp frontmatter_desc(_), do: nil

  # Hero badges for a doc: the doc_set kind + the version (when the variant is a version code).
  defp doc_badges(docset, variant) do
    kind =
      case docset && Map.get(docset, :kind_code) do
        nil -> ""
        k -> badge(k, k)
      end

    ver = if is_binary(variant) and variant =~ ~r/\d/, do: badge("v#{variant}", "default"), else: ""
    [kind, ver] |> Enum.reject(&(&1 == "")) |> Enum.join(" ")
  end

  # Per-page canonical from the set's site_url (settings) + the request path.
  defp canonical_url(nil, _conn), do: nil

  defp canonical_url(docset, conn) do
    case get_in(docset.settings, ["site_url"]) do
      nil -> nil
      base -> String.trim_trailing(base, "/") <> conn.request_path
    end
  end

  # ── search-index inspector ────────────────────────────────────────────────
  # Shows what the full-text layer actually indexed for this page: the front-matter
  # keywords (weight B) and the prose extracted from the markdown (weight C — directives,
  # fences and HTML chrome stripped). The raw markdown is never what gets searched.
  defp index_panel(nil), do: ""

  defp index_panel(index) do
    """
    <details class="kd-index">
      <summary>🔍 search index — how this page is indexed</summary>
      <p class="muted">Front-matter keywords (weight B) and the extracted prose (weight C).
      Directive syntax, fenced code and HTML are dropped — the raw markdown is never indexed.</p>
      <h3>keywords</h3>
      <pre>#{esc(index.keywords || "—")}</pre>
      <h3>extracted prose</h3>
      <pre>#{esc(index.search_text || "—")}</pre>
    </details>
    """
  end

  # ── package.json resolution ───────────────────────────────────────────────

  defp resolve_deps(json) do
    sets = Content.rows(Content.list_doc_sets())

    deps =
      ["dependencies", "devDependencies", "peerDependencies"]
      |> Enum.flat_map(fn key -> Map.get(json, key, %{}) |> Map.to_list() end)

    Enum.map(deps, fn {name, range} ->
      installed = strip_version(range)

      case Enum.find(sets, &(&1.package_name == name)) do
        nil ->
          %{name: name, range: range, docs: nil}

        s ->
          r = Content.one(Content.resolve_doc_variant(s.code, installed))
          link = if r.show_in_path, do: "/#{s.code}/#{r.code}/", else: "/#{s.code}/"
          %{name: name, range: range, installed: installed, set: s.code, variant: r.title, matched: r.matched, link: link}
      end
    end)
  end

  defp strip_version(range) do
    range
    |> to_string()
    |> String.replace(~r/^[^\d]*/, "")
    |> String.split(~r/\s+/, parts: 2)
    |> List.first()
    |> case do
      nil -> "0.0.0"
      "" -> "0.0.0"
      v -> v
    end
  end

  defp resolve_form(text, result) do
    results_html =
      case result do
        nil ->
          ""

        :bad_json ->
          ~s(<div class="kd-card" style="border-color:#fca5a5"><strong>Could not parse JSON.</strong></div>)

        rows ->
          body =
            Enum.map_join(rows, "", fn r ->
              if Map.has_key?(r, :set) do
                note = if r.matched, do: badge("matched", "default"), else: badge("fallback", "hidden")
                ~s(<tr><td><code>#{esc(r.name)}</code></td><td>#{esc(to_string(r.range))} → #{esc(r.installed)}</td><td><a href="#{r.link}">#{esc(r.variant)}</a> #{note}</td><td class="muted">#{esc(r.link)}</td></tr>)
              else
                ~s(<tr><td><code>#{esc(r.name)}</code></td><td>#{esc(to_string(r.range))}</td><td colspan="2" class="muted">no docs for this package</td></tr>)
              end
            end)

          ~s(<div class="kd-card"><table><tr><th>package</th><th>version</th><th>docs</th><th>link</th></tr>#{body}</table></div>)
      end

    """
    <h1>Resolve a project's dependencies</h1>
    <p class="muted">Paste a <code>package.json</code>; we match each dependency to a
    <code>doc_set</code> and resolve its version through <code>applies_to</code>.</p>
    <form class="kd-form" action="/resolve" method="post">
      <textarea name="package_json">#{esc(text)}</textarea>
      <p><button type="submit">Resolve</button></p>
    </form>
    #{results_html}
    """
  end

  defp sample_package_json do
    Jason.encode!(
      %{
        "name" => "my-app",
        "dependencies" => %{
          "@keenmate/web-multiselect" => "^2.1.0",
          "@keenmate/does-not-exist" => "1.0.0"
        }
      },
      pretty: true
    )
  end

  # ── helpers ───────────────────────────────────────────────────────────────

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, ""), do: map
  defp maybe_put(map, key, val), do: Map.put(map, key, val)

  defp html(conn, body), do: send_resp(put_resp_content_type(conn, "text/html"), 200, body)

  # Serve a JS asset from priv/web as a real ES module (explicit text/javascript so the
  # browser will import it). `rel` is a repo-relative path under priv/web — no traversal.
  defp send_js(conn, rel) do
    path = Path.join([File.cwd!(), "priv", "web", rel])

    if File.exists?(path) do
      conn |> put_resp_content_type("text/javascript") |> send_resp(200, File.read!(path))
    else
      send_resp(conn, 404, "missing asset: #{rel}")
    end
  end

  # Serve a CSS asset from priv/web. `rel` is a repo-relative path — no traversal.
  defp send_css(conn, rel) do
    path = Path.join([File.cwd!(), "priv", "web", rel])

    if File.exists?(path) do
      conn |> put_resp_content_type("text/css") |> send_resp(200, File.read!(path))
    else
      send_resp(conn, 404, "missing asset: #{rel}")
    end
  end


  defp not_found(conn) do
    send_resp(put_resp_content_type(conn, "text/html"), 404, View.layout("Not found", "<h1>404</h1><p>Nothing here.</p>"))
  end
end
