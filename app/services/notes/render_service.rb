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
      preprocessed = resolve_wikilinks(@content_markdown)
      html = Commonmarker.to_html(preprocessed, options: {
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

      Sanitize.fragment(html,
        elements: ALLOWED_TAGS,
        attributes: ALLOWED_ATTRIBUTES,
        protocols: {
          "a" => {"href" => ["http", "https", "mailto", :relative]},
          "img" => {"src" => ["http", "https", :relative]}
        })
    end

    private

    # Converts [[Display|uuid]] → markdown link or broken-link span before parsing.
    def resolve_wikilinks(content)
      note_cache = {}

      content.gsub(WIKILINK_RE) do
        display = $~[:display].strip
        uuid = $~[:uuid].downcase

        note = note_cache[uuid] ||= Note.active.select(:id, :slug, :title).find_by(id: uuid)

        if note
          title_attr = note.title == display ? "" : " title=\"#{CGI.escapeHTML(note.title)}\""
          "<a href=\"/notes/#{note.slug}\"#{title_attr}>#{CGI.escapeHTML(display)}</a>"
        else
          "<span class=\"wikilink-broken\" title=\"Nota não encontrada\">#{CGI.escapeHTML(display)}</span>"
        end
      end
    end
  end
end
