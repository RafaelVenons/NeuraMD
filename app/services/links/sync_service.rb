module Links
  # Synchronises note_links for a src note based on wiki-link markup in a revision.
  #
  # - Creates links present in content but not in DB
  # - Deletes links present in DB but not in content
  # - Skips self-links and links to non-existent notes (broken links are valid in content)
  # - Idempotent: safe to call multiple times with the same content
  class SyncService
    def self.call(src_note:, revision:, content:)
      new(src_note:, revision:, content:).call
    end

    def initialize(src_note:, revision:, content:)
      @src_note = src_note
      @revision = revision
      @content = content
    end

    def call
      desired = extract_desired_links
      existing = load_existing_links

      create_missing(desired, existing)
      delete_removed(desired, existing)
    end

    private

    def extract_desired_links
      Links::ExtractService.call(@content)
        .reject { |link| link[:dst_note_id] == @src_note.id.to_s.downcase }
        .select { |link| Note.active.exists?(id: link[:dst_note_id]) }
    end

    def load_existing_links
      @src_note.outgoing_links.map do |link|
        {dst_note_id: link.dst_note_id.to_s.downcase, hier_role: link.hier_role}
      end
    end

    def create_missing(desired, existing)
      (desired - existing).each do |link|
        @src_note.outgoing_links.create!(
          dst_note_id: link[:dst_note_id],
          hier_role: link[:hier_role],
          created_in_revision: @revision
        )
      end
    end

    def delete_removed(desired, existing)
      (existing - desired).each do |link|
        @src_note.outgoing_links
          .find_by(dst_note_id: link[:dst_note_id], hier_role: link[:hier_role])
          &.destroy!
      end
    end
  end
end
