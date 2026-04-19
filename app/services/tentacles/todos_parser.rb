module Tentacles
  class TodosParser
    SECTION_HEADING = /\A##\s+todos\s*\z/i
    STOP_HEADING = /\A#(?:#)?\s+\S/
    ITEM = /\A\s*-\s+\[([ xX])\]\s+(.+?)\s*\z/

    def self.parse(markdown)
      return [] if markdown.to_s.empty?
      lines = markdown.to_s.split("\n", -1)

      start = lines.index { |l| SECTION_HEADING.match?(l) }
      return [] if start.nil?

      todos = []
      ((start + 1)...lines.length).each do |i|
        line = lines[i]
        break if STOP_HEADING.match?(line)
        m = ITEM.match(line)
        next unless m
        todos << { text: m[2].strip, done: m[1].downcase == "x" }
      end
      todos
    end

    def self.replace(markdown, todos)
      body = markdown.to_s
      section = render_section(todos)
      lines = body.split("\n", -1)

      start = lines.index { |l| SECTION_HEADING.match?(l) }
      if start.nil?
        return "#{body.chomp}\n\n#{section}"
      end

      stop = ((start + 1)...lines.length).find { |i| STOP_HEADING.match?(lines[i]) } || lines.length
      prefix = lines[0...start].join("\n")
      suffix_lines = lines[stop..]
      suffix = suffix_lines.empty? ? "" : "\n" + suffix_lines.join("\n")

      rebuilt = prefix.empty? ? section : "#{prefix}\n#{section.chomp}"
      "#{rebuilt}#{suffix}"
    end

    def self.render_section(todos)
      lines = ["## Todos", ""]
      Array(todos).each do |t|
        text = t[:text] || t["text"]
        done = t[:done] || t["done"]
        mark = done ? "x" : " "
        lines << "- [#{mark}] #{text}"
      end
      lines << "" unless lines.last == ""
      lines.join("\n")
    end
  end
end
