module Links
  # Synchronises note_links for a src note based on wiki-link markup in a revision.
  #
  # - Creates links present in content but not in DB
  # - Marks inactive links that are no longer present in content
  # - Skips self-links and links to non-existent notes (broken links are valid in content)
  # - Idempotent: safe to call multiple times with the same content
  class SyncService
    include ::DomainEvents
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
          was_inactive = !existing_link.active?
          graph_changed = existing_link.hier_role != link[:hier_role] || was_inactive

          if existing_link.created_in_revision_id != @revision.id ||
              existing_link.hier_role != link[:hier_role] ||
              was_inactive
            existing_link.update!(
              hier_role: link[:hier_role],
              created_in_revision: @revision,
              active: true
            )
            publish_event("link.created", link_id: existing_link.id, src_note_id: @src_note.id, dst_note_id: link[:dst_note_id]) if was_inactive
          end

          changed ||= graph_changed
        else
          new_link = @src_note.outgoing_links.create!(
            dst_note_id: link[:dst_note_id],
            hier_role: link[:hier_role],
            created_in_revision: @revision,
            active: true
          )
          publish_event("link.created", link_id: new_link.id, src_note_id: @src_note.id, dst_note_id: link[:dst_note_id])
          changed = true
        end
      end

      changed
    end

    def delete_removed(desired)
      desired_ids = desired.map { |link| link[:dst_note_id] }.uniq
      to_deactivate = NoteLink
        .where(src_note_id: @src_note.id, active: true)
        .where.not(dst_note_id: desired_ids)

      deactivated_dst_ids = to_deactivate.pluck(:dst_note_id)
      updated = to_deactivate.update_all(active: false, updated_at: Time.current)

      if updated.positive?
        publish_event("link.deleted", src_note_id: @src_note.id, dst_note_ids: deactivated_dst_ids)
      end

      updated.positive?
    end
  end
end
