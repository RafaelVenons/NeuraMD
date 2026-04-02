module Blocks
  class SyncService
    def self.call(note:, content:)
      new(note:, content:).call
    end

    def initialize(note:, content:)
      @note = note
      @content = content
    end

    def call
      blocks = Blocks::ExtractService.call(@content)

      @note.note_blocks.delete_all

      blocks.each do |b|
        @note.note_blocks.create!(
          block_id: b.block_id,
          content: b.content,
          block_type: b.block_type,
          position: b.position
        )
      end
    end
  end
end
