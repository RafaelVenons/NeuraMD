module Notes
  class RenderService
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

      Sanitize.fragment(html,
        elements: ALLOWED_TAGS,
        attributes: ALLOWED_ATTRIBUTES,
        protocols: {
          "a" => {"href" => ["http", "https", "mailto", :relative]},
          "img" => {"src" => ["http", "https", :relative]}
        })
    end
  end
end
