# frozen_string_literal: true

module FileImports
  class SanitizeService
    QualityReport = Struct.new(:markdown, :usable, :warnings, :applied, keyword_init: true)

    CID_ABSOLUTE_THRESHOLD = 100
    CID_RATIO_THRESHOLD = 0.05
    NO_SPACE_MIN_LINES = 5
    NO_SPACE_MIN_LINE_LENGTH = 80
    NO_SPACE_RATIO_THRESHOLD = 0.3
    MAX_TITLE_LENGTH = 120

    def self.call(markdown:, filename: nil)
      new(markdown, filename).call
    end

    def initialize(markdown, filename)
      @raw = markdown.to_s
      @filename = filename
      @warnings = []
      @applied = []
    end

    def call
      if cid_token_ratio_too_high?
        return reject!(
          "PDF com encoding de fontes irrecuperavel — #{@cid_count} tokens (cid:XX) encontrados. " \
          "Re-exporte o PDF a partir do aplicativo de origem ou use OCR."
        )
      end

      if no_space_blob_detected?
        return reject!(
          "Texto do PDF sem separacao entre palavras — palavras concatenadas sem espacos. " \
          "O PDF provavelmente nao possui encoding de texto adequado. Re-exporte ou use OCR."
        )
      end

      text = @raw.dup
      text = strip_cid_tokens(text)
      text = convert_form_feeds(text)
      text = normalize_flat_headings(text)
      text = ensure_root_heading(text)
      text = strip_heading_bold(text)
      text = clean_garbage_headings(text)
      text = collapse_excessive_blanks(text)

      QualityReport.new(markdown: text, usable: true, warnings: @warnings, applied: @applied)
    end

    private

    # ── Detectores (fail-fast) ──────────────────────────────────────────────

    def cid_token_ratio_too_high?
      @cid_count = @raw.scan(/\(cid:\d+\)/).size
      return false if @cid_count.zero?

      word_count = @raw.split(/\s+/).size
      ratio = @cid_count.to_f / [word_count, 1].max
      ratio > CID_RATIO_THRESHOLD || @cid_count > CID_ABSOLUTE_THRESHOLD
    end

    def no_space_blob_detected?
      long_lines = @raw.lines.select { |l| l.strip.length > NO_SPACE_MIN_LINE_LENGTH }
      return false if long_lines.size < NO_SPACE_MIN_LINES

      no_space_count = long_lines.count { |l| l.strip.count(" ") < (l.strip.length / 20) }
      ratio = no_space_count.to_f / long_lines.size
      ratio > NO_SPACE_RATIO_THRESHOLD
    end

    # ── Transformadores ─────────────────────────────────────────────────────

    def strip_cid_tokens(text)
      return text if @cid_count.zero?

      cleaned = text.gsub(/\(cid:\d+\)/, "")
      @applied << "strip_sparse_cid_tokens"
      @warnings << "Removidos #{@cid_count} tokens (cid:XX) do output"
      cleaned
    end

    def convert_form_feeds(text)
      return text unless text.include?("\f")
      return text if text.match?(/^#\s/m)

      pages = text.split("\f").reject { |p| p.strip.empty? }
      return text if pages.size <= 1

      @applied << "form_feed_to_headings"
      @warnings << "Convertidos #{pages.size} page breaks em headings de slide"

      slide_sections = pages.map.with_index(1) do |page, idx|
        lines = page.lines.map(&:rstrip)
        lines.shift while lines.first&.strip&.empty?
        lines.pop while lines.last&.strip&.empty?
        next nil if lines.empty?

        title_line = lines.first&.strip
        if title_line && title_line.length.between?(2, MAX_TITLE_LENGTH)
          lines.shift
          lines.shift while lines.first&.strip&.empty?
          "## #{title_line}\n\n#{lines.join("\n")}"
        else
          "## Slide #{idx}\n\n#{lines.join("\n")}"
        end
      end.compact

      root_title = derive_root_title
      "# #{root_title}\n\n#{slide_sections.join("\n\n")}"
    end

    def derive_root_title
      return File.basename(@filename, File.extname(@filename)).tr("_-", " ").strip if @filename.present?
      "Documento importado"
    end

    # When a document has many ## headings but only a few spurious # headings
    # (typical of slide PDFs extracted by pymupdf4llm), demote the # to ##
    # and prepend a synthetic # root heading derived from the filename.
    FLAT_H2_MIN = 10
    SPURIOUS_H1_MAX = 5

    def normalize_flat_headings(text)
      lines = text.lines
      h1_lines = lines.each_with_index.select { |l, _| l.match?(/\A# [^#]/) }
      h2_count = lines.count { |l| l.match?(/\A## [^#]/) }

      return text if h1_lines.empty? || h2_count < FLAT_H2_MIN
      return text if h1_lines.size > SPURIOUS_H1_MAX
      # Skip if there's a single clear H1 root (normal document structure)
      return text if h1_lines.size == 1

      @applied << "normalize_flat_headings"
      @warnings << "Nivelados #{h1_lines.size} headings H1 espurios para H2 e criado indice raiz"

      normalized = lines.map do |line|
        if line.match?(/\A# [^#]/)
          "##{line}" # # Title → ## Title
        else
          line
        end
      end

      root_title = derive_root_title
      "# #{root_title}\n\n#{normalized.join}"
    end

    # When a document has only ## headings and no # root,
    # prepend a synthetic # heading from the filename so the importer
    # creates a root note that indexes all sections.
    def ensure_root_heading(text)
      return text if text.match?(/^# [^#]/m)
      h2_count = text.lines.count { |l| l.match?(/\A## [^#]/) }
      return text if h2_count < 2

      root_title = derive_root_title
      @applied << "ensure_root_heading"
      @warnings << "Criado heading raiz '#{root_title}' para indexar #{h2_count} secoes"
      "# #{root_title}\n\n#{text}"
    end

    def strip_heading_bold(text)
      changed = false
      result = text.gsub(/^(#+\s+)\*\*(.+?)\*\*\s*$/m) { changed = true; "#{$1}#{$2}" }
      if changed
        @applied << "strip_heading_bold"
        @warnings << "Removidos marcadores **bold** de headings"
      end
      result
    end

    def clean_garbage_headings(text)
      changed = false
      lines = text.lines.map do |line|
        stripped = line.chomp
        if stripped.match?(/\A#+\s*/)
          heading_text = stripped.sub(/\A#+\s*/, "").strip
          if heading_text.empty? || heading_text.match?(/\A[\W\d\s]{0,5}\z/)
            changed = true
            next "\n"
          end
        end
        line
      end

      if changed
        @applied << "clean_garbage_headings"
        @warnings << "Removidos headings vazios ou com conteudo invalido"
      end

      lines.join
    end

    def collapse_excessive_blanks(text)
      text.gsub(/\n{4,}/, "\n\n\n")
    end

    def reject!(message)
      QualityReport.new(markdown: @raw, usable: false, warnings: [message], applied: [])
    end
  end
end
