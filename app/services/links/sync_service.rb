module Links
  # Synchronises note_links for a src note based on wiki-link markup in a revision.
  #
  # - Creates links present in content but not in DB
  # - Marks inactive links that are no longer present in content
  # - Skips self-links and links to non-existent notes (broken links are valid in content)
  # - Idempotent: safe to call multiple times with the same content
  class SyncService
    Result = Struct.new(:graph_changed, keyword_init: true)

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

      changed = false
      changed ||= upsert_links(desired)
      changed ||= delete_removed(desired)

      Result.new(graph_changed: changed)
    end

    private

    def extract_desired_links
      Links::ExtractService.call(@content)
        .reject { |link| link[:dst_note_id] == @src_note.id.to_s.downcase }
        .select { |link| Note.active.exists?(id: link[:dst_note_id]) }
    end

    def upsert_links(desired)
      changed = false

      desired.each do |link|
        existing_link = NoteLink.find_by(src_note_id: @src_note.id, dst_note_id: link[:dst_note_id])

        if existing_link
          graph_changed = existing_link.hier_role != link[:hier_role] || !existing_link.active?

          if existing_link.created_in_revision_id != @revision.id ||
              existing_link.hier_role != link[:hier_role] ||
              !existing_link.active?
            existing_link.update!(
              hier_role: link[:hier_role],
              created_in_revision: @revision,
              active: true
            )
          end

          changed ||= graph_changed
        else
          @src_note.outgoing_links.create!(
            dst_note_id: link[:dst_note_id],
            hier_role: link[:hier_role],
            created_in_revision: @revision,
            active: true
          )
          changed = true
        end
      end

      changed
    end

    def delete_removed(desired)
      desired_ids = desired.map { |link| link[:dst_note_id] }.uniq
      updated = NoteLink
        .where(src_note_id: @src_note.id, active: true)
        .where.not(dst_note_id: desired_ids)
        .update_all(active: false, updated_at: Time.current)

      updated.positive?
    end
  end
end
