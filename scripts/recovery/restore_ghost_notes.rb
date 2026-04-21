# Rails runner: restore 27 "ghost" notes — revisions captured in the dev log
# (2026-04-11 .. 2026-04-21) but whose original INSERT preceded the log window.
# We fabricate minimal notes rows using best-effort title/slug derivation from
# note_headings or notes.UPDATE events; content is pulled intact from the
# logged note_revisions INSERTs (encrypted content_markdown decrypts because
# master.key is unchanged).
#
# Tag every recovered note with "recovered-2026-04-21" so the user can audit.

require "json"
require "set"
require "securerandom"

dry_run = ARGV.include?("--dry-run")

GHOST_IDS = %w[
  3456396f-f704-4856-bf1f-fc6b30a0f324 9ce66445-c797-44fc-b492-733ab42ff68e
  e15190ab-925c-4c35-80c2-9958e2b7a75e 313e284e-94c9-454e-85f0-0573f114a40e
  32a3f2c2-409b-4841-9a85-60af0a7781fc 3d29fb79-9aa1-417f-a5f1-690fdba9b047
  b563e202-791f-4da7-9a01-79a5cac11554 d03e7796-8f66-4861-895f-29c644480bf9
  fd29688e-6606-468e-8e1c-9e665c2d3306 a5f9dd4c-3108-47f4-8f3b-5fc667625d1b
  67b1fb12-d9a2-483b-9e75-b2080abff06e 42607663-d4d1-47ef-a0c5-877e3cef41eb
  51626036-9c73-4e39-ba5b-8ee7c773e840 f6b2db43-1b94-4593-8ef0-049b0ff63877
  20ed3100-3d76-497d-82a8-132f8ea231af b3323f3e-ceea-4bde-95f9-0ad9e80ab329
  c93a52d9-5c3d-4dc4-b510-6cc2a03e49d7 f4e0ef4c-0e60-4644-93e4-18a658c15820
  b4d107fd-911e-424e-9725-b2bb7077b23b 3bda1563-5f69-4709-9151-e868e8ef4d41
  c47911ff-2476-45b4-9441-9bf53af33e3f ab521beb-66da-4307-98f4-43d09e2e81e9
  914dfd3a-a4b3-4ebc-83e8-dd2dbe903512 61e57f33-c2eb-44c7-b2fc-7aa355948072
  d0ba0772-30d1-4f6f-83ce-ad8cfb505b25 b6bab7d3-c816-45a2-af41-f8a83450386b
  5847a37e-e086-4a79-b300-a4a5d1861cdc
].to_set.freeze

events_path = "tmp/recovery/events.jsonl"

revisions = Hash.new { |h, k| h[k] = [] }
headings = Hash.new { |h, k| h[k] = [] }
update_meta = {}
existing_author_ids = Set.new

File.foreach(events_path) do |line|
  e = JSON.parse(line)
  table = e["table"]
  op = e["op"]

  case table
  when "note_revisions"
    next unless op == "insert"
    d = Hash[e["columns"].zip(e["values"])]
    next unless GHOST_IDS.include?(d["note_id"])
    revisions[d["note_id"]] << d
    existing_author_ids << d["author_id"] if d["author_id"]
  when "note_headings"
    next unless op == "insert"
    d = Hash[e["columns"].zip(e["values"])]
    next unless GHOST_IDS.include?(d["note_id"])
    headings[d["note_id"]] << d
  when "notes"
    next unless op == "update"
    where = e["where"] || {}
    id = where["id"]
    next unless GHOST_IDS.include?(id)
    set = e["set"] || {}
    update_meta[id] ||= {}
    %w[slug title note_kind detected_language created_at updated_at deleted_at].each do |c|
      update_meta[id][c] = set[c] if set.key?(c)
    end
  end
end

puts "author_ids seen in ghost revisions: #{existing_author_ids.to_a.inspect}"

# Primary author for this acervo (from earlier consolidation):
DEFAULT_AUTHOR_ID = User.first&.id || "bc73b56a-4234-47b5-804c-3c3e8515d4a5"
puts "using author_id: #{DEFAULT_AUTHOR_ID}"

def slugify(text, fallback_id)
  base = text.to_s.downcase.gsub(/[^\w\s-]/, " ").gsub(/\s+/, "-").gsub(/-+/, "-").gsub(/^-|-$/, "")[0..60]
  base = "recovered-note" if base.empty?
  "#{base}-#{fallback_id[0..7]}"
end

def fallback_title(content_plain, id)
  first = content_plain.to_s.lines.map(&:strip).reject(&:empty?).first.to_s
  # drop "Status: ..." prefix to find a real title
  if first =~ /^Status:/
    first = content_plain.to_s.lines.map(&:strip).reject(&:empty?)[1] || first
  end
  first = first[0..80]
  first = "Recovered note #{id[0..7]}" if first.empty?
  first
end

ActiveRecord::Base.transaction do
  conn = ActiveRecord::Base.connection

  # Ensure recovered tag
  recovered_tag_id = conn.select_value("SELECT id FROM tags WHERE name = 'recovered-2026-04-21'")
  unless recovered_tag_id
    recovered_tag_id = SecureRandom.uuid
    unless dry_run
      conn.execute("INSERT INTO tags (id, name, color_hex, tag_scope, created_at, updated_at) VALUES (#{conn.quote(recovered_tag_id)}, 'recovered-2026-04-21', '#ff6b6b', 'user', NOW(), NOW())")
    end
  end

  restored = 0
  skipped = 0

  GHOST_IDS.each do |nid|
    revs = revisions[nid].sort_by { |r| r["created_at"].to_s }
    if revs.empty?
      puts "  SKIP #{nid}: no revisions"
      skipped += 1
      next
    end

    # Skip if note already exists
    exists = conn.select_value("SELECT id FROM notes WHERE id = #{conn.quote(nid)}").to_s != ""
    if exists
      puts "  SKIP #{nid}: already in DB"
      skipped += 1
      next
    end

    meta = update_meta[nid] || {}
    earliest = revs.first
    latest = revs.last

    # Title preference: UPDATE title > H1 heading > first non-empty content line
    h1 = (headings[nid] || []).select { |h| h["level"].to_i == 1 }.sort_by { |h| h["position"].to_i }.first
    h_any = (headings[nid] || []).sort_by { |h| h["position"].to_i }.first
    title = meta["title"] || (h1 && h1["text"]) || (h_any && h_any["text"]) || fallback_title(latest["content_plain"], nid)
    title = title.to_s[0..200]

    slug = meta["slug"] || slugify(title, nid)

    # Ensure unique slug
    suffix = 0
    base_slug = slug
    while conn.select_value("SELECT 1 FROM notes WHERE slug = #{conn.quote(slug)}").to_s != ""
      suffix += 1
      slug = "#{base_slug}-#{suffix}"
      break if suffix > 50
    end

    created_at = earliest["created_at"]
    updated_at = latest["updated_at"] || latest["created_at"]

    puts "  RESTORE #{nid}"
    puts "    slug=#{slug}"
    puts "    title=#{title[0..80]}"
    puts "    revs=#{revs.size}  created=#{created_at}"

    unless dry_run
      # Insert note (head_revision_id will be set after revisions insert)
      conn.execute(<<~SQL)
        INSERT INTO notes (id, slug, title, note_kind, detected_language, created_at, updated_at)
        VALUES (
          #{conn.quote(nid)},
          #{conn.quote(slug)},
          #{conn.quote(title)},
          'note',
          NULL,
          #{conn.quote(created_at)},
          #{conn.quote(updated_at)}
        )
      SQL

      # Insert revisions (preserve ids; null base_revision_id that points outside the set)
      valid_rev_ids = revs.map { |r| r["id"] }.compact.to_set
      revs.each do |r|
        rid = r["id"] || SecureRandom.uuid
        base = r["base_revision_id"]
        base = nil unless base && valid_rev_ids.include?(base)
        author = r["author_id"] || DEFAULT_AUTHOR_ID
        conn.execute(<<~SQL)
          INSERT INTO note_revisions (
            id, note_id, revision_kind, content_markdown, content_plain,
            properties_data, base_revision_id, author_id, ai_generated,
            change_summary, created_at, updated_at
          ) VALUES (
            #{conn.quote(rid)},
            #{conn.quote(nid)},
            #{conn.quote(r["revision_kind"] || "checkpoint")},
            #{conn.quote(r["content_markdown"])},
            #{conn.quote(r["content_plain"])},
            #{conn.quote(r["properties_data"] || "{}")},
            #{base.nil? ? "NULL" : conn.quote(base)},
            #{conn.quote(author)},
            #{r["ai_generated"] == true ? "TRUE" : "FALSE"},
            #{r["change_summary"].nil? ? "NULL" : conn.quote(r["change_summary"])},
            #{conn.quote(r["created_at"])},
            #{conn.quote(r["updated_at"])}
          )
        SQL
      end

      # Set head_revision_id to latest
      head_id = revs.last["id"] || revs.last["id"]
      conn.execute("UPDATE notes SET head_revision_id = #{conn.quote(head_id)} WHERE id = #{conn.quote(nid)}")

      # Tag with recovered-2026-04-21
      conn.execute(<<~SQL)
        INSERT INTO note_tags (note_id, tag_id, created_at)
        VALUES (#{conn.quote(nid)}, #{conn.quote(recovered_tag_id)}, NOW())
        ON CONFLICT DO NOTHING
      SQL
    end
    restored += 1
  end

  puts ""
  puts "=== summary ==="
  puts "restored: #{restored}"
  puts "skipped:  #{skipped}"

  if dry_run
    puts "\n(dry-run: rolling back)"
    raise ActiveRecord::Rollback
  end
end

puts "\nfinal counts:"
puts "  notes:     #{ActiveRecord::Base.connection.select_value('SELECT COUNT(*) FROM notes')}"
puts "  revisions: #{ActiveRecord::Base.connection.select_value('SELECT COUNT(*) FROM note_revisions')}"
puts "  recovered-2026-04-21 tagged: #{ActiveRecord::Base.connection.select_value("SELECT COUNT(*) FROM note_tags nt JOIN tags t ON t.id=nt.tag_id WHERE t.name='recovered-2026-04-21'")}"
