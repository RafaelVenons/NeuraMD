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

      upsert_links(desired)
      delete_removed(desired)
    end

    private

    def extract_desired_links
      Links::ExtractService.call(@content)
        .reject { |link| link[:dst_note_id] == @src_note.id.to_s.downcase }
        .select { |link| Note.active.exists?(id: link[:dst_note_id]) }
    end

    def upsert_links(desired)
      desired.each do |link|
        existing_link = @src_note.outgoing_links.find_by(dst_note_id: link[:dst_note_id])

        if existing_link
          next if existing_link.hier_role == link[:hier_role] && existing_link.created_in_revision_id == @revision.id

          existing_link.update!(
            hier_role: link[:hier_role],
            created_in_revision: @revision
          )
        else
          @src_note.outgoing_links.create!(
            dst_note_id: link[:dst_note_id],
            hier_role: link[:hier_role],
            created_in_revision: @revision
          )
        end
      end
    end

    def delete_removed(desired)
      desired_ids = desired.map { |link| link[:dst_note_id] }.uniq
      @src_note.outgoing_links.where.not(dst_note_id: desired_ids).find_each(&:destroy!)
    end
  end
end
