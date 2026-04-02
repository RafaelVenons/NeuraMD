module Headings
  class SyncService
    def self.call(note:, content:)
      new(note:, content:).call
    end

    def initialize(note:, content:)
      @note = note
      @content = content
    end

    def call
      headings = Headings::ExtractService.call(@content)

      @note.note_headings.delete_all

      headings.each do |h|
        @note.note_headings.create!(
          level: h.level,
          text: h.text,
          slug: h.slug,
          position: h.position
        )
      end
    end
  end
end
