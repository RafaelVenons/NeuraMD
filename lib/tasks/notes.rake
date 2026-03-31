namespace :notes do
  desc "Re-sync wiki-links for all active notes with head revisions"
  task reindex: :environment do
    notes = Note.active.where.not(head_revision_id: nil).includes(:head_revision)
    total = notes.count
    synced = 0

    puts "Reindexing links for #{total} notes..."

    notes.find_each do |note|
      revision = note.head_revision
      next unless revision

      content = begin
        revision.content_markdown.to_s
      rescue ActiveRecord::Encryption::Errors::Decryption => e
        puts "  SKIP #{note.slug} (revision #{revision.id}): #{e.class}"
        next
      end

      Links::SyncService.call(src_note: note, revision: revision, content: content)
      synced += 1
    end

    puts "Done. Synced #{synced}/#{total} notes."
  end
end
