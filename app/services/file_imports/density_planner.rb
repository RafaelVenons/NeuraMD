# frozen_string_literal: true

module FileImports
  # Given a list of matched TOC entries (with :body_line) and the full markdown,
  # decides which entries become their own note and which are merged into their
  # parent based on content density. Pure Ruby, no I/O.
  #
  # Output tree shape:
  #   {
  #     main:     { title:, content:, children: [Node, …] },
  #     stats:    { split_count:, merged_count:, blocklisted_count:, total_notes: }
  #   }
  # Each Node = { title:, content:, level:, children: [Node, …] }
  class DensityPlanner
    # Names that should NEVER be their own note (content gets merged into parent
    # or dropped). Normalized (lowercase, no accents) for matching.
    BLOCKLIST = [
      "preface", "prefacio",
      "acknowledgments", "acknowledgements", "agradecimentos",
      "exercises", "exercicios", "problems",
      "epilogue and references", "notas bibliograficas e historicas",
      "further reading", "further reading and bibliographic notes", "referencias",
      "references", "bibliography",
      "index", "subject index", "author index",
      "figures", "tables", "list of figures", "list of tables",
      "copyright", "cover", "title page", "capa", "folha de rosto",
      "creditos", "epigraph", "epigrafe",
      "publishers acknowledgements"
    ].to_set.freeze

    DEFAULT_THRESHOLD_LINES = 30

    def self.call(markdown:, matched_entries:, root_title:, threshold: DEFAULT_THRESHOLD_LINES)
      new(markdown, matched_entries, root_title, threshold).call
    end

    def initialize(markdown, matched_entries, root_title, threshold)
      @lines = markdown.to_s.lines.map(&:chomp)
      @entries = matched_entries.select { |e| e[:body_line] }
      @root_title = root_title.to_s.presence || "Documento importado"
      @threshold = threshold
    end

    def call
      if @entries.empty?
        return {
          main: { title: @root_title, content: @lines.join("\n"), level: 0, children: [] },
          stats: { split_count: 0, merged_count: 0, blocklisted_count: 0, total_notes: 1 }
        }
      end

      # Sort by body_line and compute spans
      sorted = @entries.sort_by { |e| e[:body_line] }
      sorted.each_with_index do |e, i|
        next_line = (i == sorted.size - 1) ? @lines.size : sorted[i + 1][:body_line]
        e[:span_start] = e[:body_line]
        e[:span_end]   = next_line - 1
        e[:content]    = extract_content(e[:span_start], e[:span_end])
        e[:density]    = measure_density(e[:content])
        e[:blocklisted] = blocklisted?(e[:title])
      end

      # Root content = everything before the first matched body line
      first = sorted.first
      root_content = @lines[0...first[:body_line]].join("\n")

      # Build hierarchical tree by entry levels (preserving order)
      tree = build_tree(sorted, root_content)

      # Bottom-up: merge nodes below threshold or blocklisted into their parent
      stats = { split_count: 0, merged_count: 0, blocklisted_count: 0 }
      collapse!(tree[:children], tree, stats)

      stats[:split_count] = count_splits(tree[:children])
      stats[:total_notes] = 1 + stats[:split_count]

      { main: tree, stats: stats }
    end

    private

    def extract_content(start_line, end_line)
      return "" if start_line > end_line || start_line.negative?
      @lines[start_line..end_line].to_a.join("\n")
    end

    # "Density" = non-blank, non-heading lines (prose + list items count).
    def measure_density(content)
      content.to_s.lines.count do |l|
        s = l.strip
        next false if s.empty?
        next false if s.match?(/\A#+\s/) # skip headings
        true
      end
    end

    def blocklisted?(title)
      BLOCKLIST.include?(normalize_title(title))
    end

    def normalize_title(text)
      s = text.to_s.downcase
      s = s.tr("áàâãäéèêëíìîïóòôõöúùûüç", "aaaaaeeeeiiiiooooouuuuc")
      s = s.gsub(/[^\p{L}\p{N}\s]/, " ")
      s.split.join(" ")
    end

    # Build a hierarchical tree. Each entry becomes a node; deeper-level entries
    # become children of the nearest preceding entry with a lower level.
    def build_tree(sorted, root_content)
      root = { title: @root_title, content: root_content, level: 0, children: [],
               density: measure_density(root_content) }

      stack = [root]

      sorted.each do |e|
        node = {
          title: e[:title],
          number: e[:number],
          content: e[:content],
          level: e[:level],
          density: e[:density],
          blocklisted: e[:blocklisted],
          children: []
        }

        # Pop stack until we find a parent with lower level than this node
        stack.pop while stack.size > 1 && stack.last[:level] >= node[:level]

        stack.last[:children] << node
        stack.push(node)
      end

      root
    end

    # Post-order: merge below-threshold or blocklisted nodes into their parent.
    # Mutates the tree in place.
    def collapse!(children, parent, stats)
      return if children.nil? || children.empty?

      # Recurse first so leaves are evaluated before their parents
      children.each { |c| collapse!(c[:children], c, stats) }

      kept = []
      children.each do |c|
        if c[:blocklisted]
          stats[:blocklisted_count] += 1
          # End-matter: drop content, don't pollute parent
          next
        end

        if c[:density] < @threshold && c[:children].empty?
          stats[:merged_count] += 1
          # Fold this small child back into the parent's content (with heading
          # preserved as inline markdown, so it reads naturally).
          parent[:content] = "#{parent[:content]}\n\n#{c[:content]}".strip
          parent[:density] = (parent[:density] || 0) + c[:density]
          next
        end

        kept << c
      end

      children.replace(kept)
    end

    def count_splits(nodes)
      return 0 if nodes.nil?
      nodes.sum { |n| 1 + count_splits(n[:children]) }
    end
  end
end
