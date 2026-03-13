module Notes
  class RenderService
    # Matches [[Display Text|uuid]] and [[Display Text|f/c/b:uuid]]
    WIKILINK_RE = /\[\[(?<display>[^\]|]+)\|(?<role>[fcb]:)?(?<uuid>[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\]\]/i

    ALLOWED_TAGS = %w[
      h1 h2 h3 h4 h5 h6
      p br hr
      ul ol li
      blockquote pre code
      strong em s del ins mark
      a img
      table thead tbody tr th td
      div span
      sup sub
      details summary
    ].freeze

    ALLOWED_ATTRIBUTES = {
      "a" => %w[href title target rel],
      "img" => %w[src alt title width height],
      "code" => %w[class],
      "pre" => %w[class],
      "div" => %w[class],
      "span" => %w[class],
      "th" => %w[align],
      "td" => %w[align]
    }.freeze

    def self.call(content_markdown)
      new(content_markdown).call
    end

    def initialize(content_markdown)
      @content_markdown = content_markdown.to_s.encode("UTF-8")
    end

    def call
      html = Commonmarker.to_html(@content_markdown, options: {
        render: {unsafe: false},
        extension: {
          strikethrough: true,
          tagfilter: true,
          table: true,
          autolink: true,
          tasklist: true,
          superscript: true,
          footnotes: true
        }
      })

      sanitized = Sanitize.fragment(html,
        elements: ALLOWED_TAGS,
        attributes: ALLOWED_ATTRIBUTES,
        protocols: {
          "a" => {"href" => ["http", "https", "mailto", :relative]},
          "img" => {"src" => ["http", "https", :relative]}
        })

      # Resolve wiki-links after sanitization so that [[Display|uuid]] literal
      # text (which CommonMarker passes through unchanged) is converted to
      # proper anchor/broken-link markup. We inject HTML directly so it bypasses
      # Sanitize — we control every byte of what is injected (display text is
      # always CGI-escaped).
      resolve_wikilinks(sanitized)
    end

    private

    # Converts [[Display|uuid]] and [[Display|role:uuid]] to anchor tags or
    # broken-link spans. Operates on already-rendered HTML.
    ROLE_CLASS = {
      "f" => "wikilink-father",
      "c" => "wikilink-child",
      "b" => "wikilink-brother"
    }.freeze

    def resolve_wikilinks(html)
      note_cache = {}

      html.gsub(WIKILINK_RE) do
        display    = $~[:display].strip
        uuid       = $~[:uuid].downcase
        role_key   = $~[:role]&.chomp(":")
        role_class = ROLE_CLASS[role_key] || "wikilink-null"

        note = note_cache[uuid] ||= Note.active.select(:id, :slug, :title).find_by(id: uuid)

        if note
          title_attr = note.title == display ? "" : " title=\"#{CGI.escapeHTML(note.title)}\""
          "<a href=\"/notes/#{note.slug}\" class=\"wikilink #{role_class}\" data-uuid=\"#{uuid}\"#{title_attr}>#{CGI.escapeHTML(display)}</a>"
        else
          "<span class=\"wikilink-broken\" title=\"Nota não encontrada\">#{CGI.escapeHTML(display)}</span>"
        end
      end
    end
  end
end
