module Tentacles
  class TodosService
    def self.read(note)
      body = note.head_revision&.content_markdown.to_s
      TodosParser.parse(body)
    end

    def self.write(note:, todos:, author: nil)
      normalized = normalize(todos)
      current = read(note)
      return current if normalized == current

      body = note.head_revision&.content_markdown.to_s
      new_body = TodosParser.replace(body, normalized)
      Notes::CheckpointService.call(note: note, content: new_body, author: author)
      normalized
    end

    def self.normalize(todos)
      Array(todos).filter_map do |raw|
        text = (raw[:text] || raw["text"]).to_s.strip
        next nil if text.empty?
        done_raw = raw.key?(:done) ? raw[:done] : raw["done"]
        { text: text, done: truthy?(done_raw) }
      end
    end

    def self.truthy?(value)
      case value
      when true then true
      when false, nil then false
      when Numeric then !value.zero?
      when String then %w[1 true t yes on].include?(value.downcase)
      else false
      end
    end
  end
end
