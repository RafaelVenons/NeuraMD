module Notes
  class MergeService
    Result = Struct.new(:source, :target, :revision, keyword_init: true)

    def self.call(source:, target:, author:)
      new(source:, target:, author:).call
    end

    def initialize(source:, target:, author:)
      @source = source
      @target = target
      @author = author
    end

    def call
      validate!

      ActiveRecord::Base.transaction do
        revision = append_content
        move_incoming_links
        create_redirect
        @source.soft_delete!

        Result.new(source: @source, target: @target, revision:)
      end
    end

    private

    def validate!
      raise ArgumentError, "Cannot merge a note into itself" if @source.id == @target.id
      raise ArgumentError, "Source note is deleted" if @source.deleted?
    end

    def append_content
      target_content = @target.head_revision&.content_markdown.to_s
      source_content = @source.head_revision&.content_markdown.to_s

      merged = "#{target_content}\n\n---\n\n<!-- Merged from: #{@source.title} -->\n\n#{source_content}"

      result = Notes::CheckpointService.call(
        note: @target,
        content: merged,
        author: @author
      )
      result.revision
    end

    def move_incoming_links
      @source.incoming_links.find_each do |link|
        existing = NoteLink.find_by(src_note_id: link.src_note_id, dst_note_id: @target.id)
        if existing
          link.destroy
        else
          link.update!(dst_note_id: @target.id)
        end
      end
    end

    def create_redirect
      SlugRedirect.where(slug: @source.slug).delete_all
      @target.slug_redirects.create!(slug: @source.slug)
    end
  end
end
