require "json"

class PlanToNotesImporter
  SOURCE_PATH = Rails.root.join("PLAN.md")
  IMPORT_USER_EMAIL = "plan-import@neuramd.local"
  IMPORT_USER_PASSWORD = "password123"
  MIN_LINES = 10
  MAX_LINES = 80
  BODY_TARGET = 46
  BODY_MAX = 58
  IMPORT_TAGS = %w[plan plan-import iniciativa estrutura-sistemica].freeze
  SIBLING_THEMES = %w[catalogo_erros testes_validacao wikilinks typewriter ia_queue tts_audio].freeze
  THEME_RULES = {
    "catalogo_erros" => /gotcha|erro|falha|diagnost|incident|pitfall|evitar|quebrou|bug/i,
    "testes_validacao" => /teste|testes|rspec|playwright|cuprite|aceitacao|validacao|regress/i,
    "wikilinks" => /wikilink|\[\[|\]\]|target_is_parent|target_is_child|same_level/i,
    "typewriter" => /typewriter|preview-editavel|preview editavel|cursor centrado/i,
    "ia_queue" => /fila|queue|job|jobs|async|assincron|worker|review|traducao|traduz/i,
    "grafo" => /grafo|graph|backlinks|force-?directed|nodos|arestas/i,
    "infra_storage" => /docker|compose|postgres|redis|storage|active storage|caddy|nginx/i,
    "tts_audio" => /tts|elevenlabs|fish audio|kokoro|mfa|forced align/i
  }.freeze

  Node = Struct.new(:title, :level, :body_lines, :children, :parent, :start_line, :end_line, keyword_init: true)
  Item = Struct.new(
    :key,
    :node,
    :part_index,
    :part_total,
    :title,
    :heading_text,
    :body_lines,
    :note,
    :parent_item,
    :child_items,
    :brother_items,
    :sibling_anchor,
    :themes,
    keyword_init: true
  )

  def call
    @import_user = ensure_import_user!
    @tag_cache = {}
    root = parse_plan
    items = build_items(root)
    wire_relationships(items)

    ActiveRecord::Base.transaction do
      delete_previous_import!
      create_note_shells!(items)
      write_note_contents!(items)
    end

    print_report(items)
  end

  private

  def ensure_import_user!
    User.find_or_create_by!(email: IMPORT_USER_EMAIL) do |user|
      user.password = IMPORT_USER_PASSWORD
      user.password_confirmation = IMPORT_USER_PASSWORD
    end
  end

  def delete_previous_import!
    imported_notes = Note.joins(:tags).where(tags: {name: "plan-import"})
    legacy_prefixed_notes = Note.where("title LIKE ?", "PLAN / %")
    notes = Note.where(id: imported_notes.select(:id)).or(Note.where(id: legacy_prefixed_notes.select(:id))).distinct
    note_ids = notes.pluck(:id)
    return if note_ids.empty?

    revision_ids = NoteRevision.where(note_id: note_ids).pluck(:id)

    Note.where(id: note_ids).update_all(head_revision_id: nil)
    NoteTag.where(note_id: note_ids).delete_all
    NoteLink.where(src_note_id: note_ids).or(NoteLink.where(dst_note_id: note_ids)).delete_all
    NoteRevision.where(id: revision_ids).delete_all
    Note.where(id: note_ids).delete_all
  end

  def parse_plan
    lines = File.read(SOURCE_PATH).lines.map(&:chomp)
    nodes = []
    stack = []
    in_fence = false

    lines.each_with_index do |line, index|
      line_number = index + 1
      in_fence = !in_fence if fence_line?(line)
      heading = !in_fence && parse_heading(line)

      if heading
        while stack.any? && stack.last.level >= heading[:level]
          stack.pop.end_line = line_number - 1
        end

        node = Node.new(
          title: heading[:title],
          level: heading[:level],
          body_lines: [],
          children: [],
          parent: nil,
          start_line: line_number,
          end_line: nil
        )
        if stack.any?
          node.parent = stack.last
          stack.last.children << node
        end
        nodes << node
        stack << node
      else
        stack.last&.body_lines&.push(line)
      end
    end

    stack.each { |node| node.end_line ||= lines.size }
    nodes.each { |node| node.body_lines = trim_blank_lines(node.body_lines) }
    nodes.first
  end

  def build_items(root)
    @items = []
    visit_node(root)
    @items
  end

  def visit_node(node)
    chunks = split_body_lines(node.body_lines)
    chunks = [["Sem corpo próprio; esta nota organiza as subnotas desta seção."]] if chunks.empty?

    node_items = chunks.each_with_index.map do |chunk_lines, index|
      title = node.title
      title = "#{title} — Parte #{index + 1}" if chunks.size > 1

      item = Item.new(
        key: "#{node.title}::#{index + 1}",
        node: node,
        part_index: index,
        part_total: chunks.size,
        title: title,
        heading_text: node.title,
        body_lines: chunk_lines,
        child_items: [],
        brother_items: [],
        sibling_anchor: nil,
        themes: extract_themes(node, chunk_lines)
      )
      @items << item
      item
    end

    child_first_items = node.children.filter_map do |child|
      child_items = visit_node(child)
      child_items.first
    end

    first_item = node_items.first
    first_item.child_items.concat(node_items.drop(1))
    first_item.child_items.concat(child_first_items)

    node_items
  end

  def wire_relationships(items)
    first_item_by_node = items.group_by(&:node).transform_values(&:first)

    items.each do |item|
      if item.part_index.zero?
        parent = item.node.parent && first_item_by_node[item.node.parent]
        item.parent_item = parent
      else
        item.parent_item = first_item_by_node[item.node]
      end
    end

    first_items = items.select { |item| item.part_index.zero? && item.node.level >= 3 }
    anchors_by_theme = {}

    first_items.each do |item|
      item.themes.each do |theme|
        next unless SIBLING_THEMES.include?(theme)

        anchor = anchors_by_theme[theme]
        next if anchor.nil?
        next if structurally_related?(item, anchor)

        item.sibling_anchor ||= anchor
      end

      item.themes.each do |theme|
        next unless SIBLING_THEMES.include?(theme)

        anchors_by_theme[theme] ||= item
      end
    end

    items.each do |item|
      item.child_items = item.child_items.compact.uniq
      item.brother_items = item.brother_items.compact.uniq - [item]
      item.brother_items << item.sibling_anchor if item.sibling_anchor
      item.brother_items = item.brother_items.compact.uniq - [item]
    end
  end

  def create_note_shells!(items)
    items.each do |item|
      item.note = Note.create!(
        title: item.title,
        note_kind: "markdown",
        detected_language: "pt-BR"
      )
      attach_tags!(item)
    end
  end

  def write_note_contents!(items)
    items.each do |item|
      content = build_content(item)
      Notes::CheckpointService.call(note: item.note, content: content, author: @import_user)
    end
  end

  def build_content(item)
    lines = []
    heading_level = [[item.node.level, 1].max, 4].min

    lines << ("#" * heading_level) + " " + item.heading_text
    lines << ""
    lines << "Origem: `PLAN.md:#{item.node.start_line}-#{item.node.end_line}`"
    lines << "Profundidade: H#{item.node.level}"
    lines << "Parte: #{item.part_index + 1}/#{item.part_total}" if item.part_total > 1
    lines << "Trilha: #{breadcrumb_for(item.node)}"
    lines << parent_line(item)
    lines << "Linha-guia: notas entre #{MIN_LINES} e #{MAX_LINES} linhas; esta importa a árvore do plano."
    lines << theme_line(item)

    if item.brother_items.any?
      lines << "Relacionadas:"
      item.brother_items.each do |related|
        lines << "- #{wikilink_for(related, :b)}"
      end
    else
      lines << "Relacionadas: nenhuma"
    end

    if item.child_items.any?
      lines << "Indice estrutural sequencial:"
      item.child_items.each_with_index do |child, index|
        lines << "#{index + 1}. #{wikilink_for(child, :c)}"
      end
    else
      lines << "Indice estrutural: sem filhos diretos"
    end

    lines << ""
    lines.concat(item.body_lines)
    lines = pad_short_note(lines, item)
    lines.join("\n")
  end

  def parent_line(item)
    return "Pai: raiz do plano" unless item.parent_item

    "Pai: #{item.parent_item.title} (referência estrutural; o índice sequencial fica na nota pai com `c:`)"
  end

  def attach_tags!(item)
    tag_names_for(item).each do |tag_name|
      NoteTag.find_or_create_by!(note: item.note, tag: ensure_tag!(tag_name))
    end
  end

  def tag_names_for(item)
    tags = IMPORT_TAGS.dup
    tags << "plan-h#{item.node.level}"
    tags << "plan-raiz" if item.parent_item.nil?
    tags << "plan-estrutura" if item.child_items.any?
    tags << "plan-fragmento" if item.part_total > 1
    tags.concat(item.themes.map { |theme| "plan-#{theme.tr('_', '-')}" })
    tags.uniq
  end

  def ensure_tag!(name)
    @tag_cache[name] ||= Tag.find_or_create_by!(name:) do |tag|
      tag.tag_scope = "note"
    end
  end

  def pad_short_note(lines, item)
    return lines if lines.size >= MIN_LINES

    missing = MIN_LINES - lines.size
    filler = [
      "",
      "Estrutura:",
      "- titulo: #{item.heading_text}",
      "- filhos_diretos: #{item.child_items.size}",
      "- relacionadas: #{item.brother_items.size}",
      "- role_pai: #{item.parent_item ? 'f:' : 'raiz'}"
    ]

    lines + filler.first(missing)
  end

  def wikilink_for(item, role)
    role_prefix = case role
    when :f then "f:"
    when :c then "c:"
    when :b then "b:"
    else nil
    end

    payload = role_prefix ? "#{role_prefix}#{item.note.id}" : item.note.id
    "[[#{item.title}|#{payload}]]"
  end

  def split_body_lines(lines)
    return [] if lines.empty?

    segments = collect_segments(lines)
    chunks = []
    current = []

    segments.each do |segment|
      if current.any? && current.size + segment.size > BODY_MAX
        chunks << trim_blank_lines(current)
        current = []
      end

      if segment.size > BODY_MAX
        split_large_segment(segment).each do |part|
          if current.any?
            chunks << trim_blank_lines(current)
            current = []
          end
          chunks << trim_blank_lines(part)
        end
      else
        current.concat(segment)
      end

      if current.size >= BODY_TARGET
        chunks << trim_blank_lines(current)
        current = []
      end
    end

    chunks << trim_blank_lines(current) if current.any?
    rebalance_chunks(chunks)
  end

  def collect_segments(lines)
    segments = []
    current = []
    in_fence = false

    lines.each do |line|
      current << line
      in_fence = !in_fence if fence_line?(line)
      next if in_fence

      if line.strip.empty?
        segments << current
        current = []
      end
    end

    segments << current if current.any?
    segments
  end

  def split_large_segment(segment)
    return [segment] if segment.size <= BODY_MAX

    segment.each_slice(BODY_MAX).map(&:dup)
  end

  def rebalance_chunks(chunks)
    chunks = chunks.reject(&:empty?)
    return chunks if chunks.size < 2

    balanced = []
    queue = chunks.map(&:dup)

    until queue.empty?
      current = queue.shift
      if current.size < 6 && queue.any?
        current.concat(queue.shift)
      end
      balanced << trim_blank_lines(current)
    end

    balanced
  end

  def trim_blank_lines(lines)
    trimmed = lines.dup
    trimmed.shift while trimmed.first&.strip == ""
    trimmed.pop while trimmed.last&.strip == ""
    trimmed
  end

  def parse_heading(line)
    match = line.match(/^(#+)\s+(.*)$/)
    return nil unless match
    return nil if match[1].length > 4

    { level: match[1].length, title: match[2].strip }
  end

  def fence_line?(line)
    line.strip.start_with?("```")
  end

  def breadcrumb_for(node)
    lineage = []
    current = node

    while current
      lineage << current.title
      current = current.parent
    end

    lineage.reverse.join(" > ")
  end

  def theme_line(item)
    return "Temas: nenhum catalogado" if item.themes.empty?

    "Temas: " + item.themes.join(", ")
  end

  def structurally_related?(left, right)
    return true if left.node == right.node
    return true if ancestor_node?(left.node, right.node)
    return true if ancestor_node?(right.node, left.node)

    false
  end

  def ancestor_node?(candidate_ancestor, node)
    current = node.parent

    while current
      return true if current == candidate_ancestor

      current = current.parent
    end

    false
  end

  def extract_themes(node, chunk_lines)
    haystack = ([node.title] + chunk_lines.first(18)).join("\n")

    THEME_RULES.each_with_object([]) do |(theme, matcher), themes|
      themes << theme if haystack.match?(matcher)
    end
  end

  def print_report(items)
    counts = items.map { |item| build_content(item).lines.count }
    puts JSON.pretty_generate(
      imported_notes: items.size,
      min_lines: counts.min,
      max_lines: counts.max,
      roots: items.count { |item| item.parent_item.nil? },
      sibling_catalog_links: items.sum { |item| item.brother_items.size },
      themed_items: items.count { |item| item.themes.any? }
    )
  end
end

PlanToNotesImporter.new.call
