# Rails runner: replay state.json into the dev DB.
#
# Usage:
#   RAILS_ENV=development bundle exec rails runner scripts/recovery/restore.rb [--dry-run]
#
# Strategy:
#   1. Re-id the currently existing user (email=rafaelsg998@gmail.com) to the
#      old user id found in revisions.author_id. This preserves the login
#      session with the password the user just set, while making FK references
#      align.
#   2. Truncate all content tables (they should be empty after the wipe).
#   3. Raw-INSERT notes → revisions → tags → note_tags → note_links →
#      note_aliases → slug_redirects → property_definitions. All inside a
#      single transaction.
#   4. Ciphertext (content_markdown) is inserted as-is — the master.key is
#      unchanged, so decryption will continue to work.
#
# After restore: SyncService will rebuild note_headings / note_blocks lazily
# on next save. Graph / search will pick up immediately.

require "json"

dry_run = ARGV.include?("--dry-run")

state_path = ENV["STATE_JSON"] || "tmp/recovery/state.json"
state = JSON.parse(File.read(state_path))
puts "loaded #{state['notes'].size} notes, #{state['revisions'].size} revisions from #{state_path}"

author_id = state["author_id_in_revisions"].first
raise "no author_id in state" unless author_id

conn = ActiveRecord::Base.connection

# --- identity stitch -----------------------------------------------------
current_user = conn.select_one("SELECT id, email FROM users WHERE email = 'rafaelsg998@gmail.com'")
raise "no post-wipe user row with email rafaelsg998@gmail.com — create one first" unless current_user

if current_user["id"] == author_id
  puts "current user already has old id; no re-id needed"
else
  puts "re-id: #{current_user['id']} -> #{author_id}"
  unless dry_run
    conn.execute("UPDATE users SET id = #{conn.quote(author_id)} WHERE email = 'rafaelsg998@gmail.com'")
  end
end

# --- safety: confirm target tables are empty ----------------------------
%w[notes note_revisions tags note_tags note_links note_aliases slug_redirects
   note_headings note_blocks property_definitions].each do |t|
  count = conn.select_value("SELECT COUNT(*) FROM #{t}").to_i
  if count > 0
    warn "  #{t} has #{count} rows (will be truncated)"
  end
end

def insert_many(conn, table, rows, column_override: nil)
  return 0 if rows.empty?
  cols = column_override || rows.first.keys.reject { |k| k.start_with?("_") }
  inserted = 0
  rows.each_slice(500) do |batch|
    values_sql = batch.map do |row|
      "(" + cols.map { |c| conn.quote(row[c]) }.join(",") + ")"
    end.join(",")
    conn.execute("INSERT INTO #{table} (#{cols.join(',')}) VALUES #{values_sql}")
    inserted += batch.size
  end
  inserted
end

ActiveRecord::Base.transaction do
  # Clear content tables (users preserved)
  puts "\ntruncating content tables..."
  unless dry_run
    # Order matters for FK cascades; use CASCADE to be safe.
    conn.execute("TRUNCATE TABLE note_tags, note_links, note_aliases, slug_redirects, note_headings, note_blocks, note_revisions, notes, tags, property_definitions CASCADE")
  end

  # Tags first (no FK from tags)
  tag_cols = %w[id name color_hex icon tag_scope created_at updated_at]
  tags_rows = state["tags"].map { |t| tag_cols.each_with_object({}) { |c, h| h[c] = t[c] } }
  puts "tags: #{tags_rows.size}"
  insert_many(conn, "tags", tags_rows, column_override: tag_cols) unless dry_run

  # Property definitions
  pd_cols = %w[id key value_type label description config system archived position created_at updated_at]
  pd_rows = state["property_definitions"].map do |p|
    id = p["id"] || SecureRandom.uuid
    pd_cols.each_with_object({}) { |c, h| h[c] = (c == "id" ? id : p[c]) }
  end
  puts "property_definitions: #{pd_rows.size}"
  insert_many(conn, "property_definitions", pd_rows, column_override: pd_cols) unless dry_run

  # Notes (head_revision_id temporarily NULL to avoid FK to yet-uninserted revisions)
  note_cols = %w[id slug title note_kind detected_language created_at updated_at deleted_at]
  note_rows = state["notes"].map do |n|
    note_cols.each_with_object({}) { |c, h| h[c] = n[c] }
  end
  puts "notes: #{note_rows.size}"
  insert_many(conn, "notes", note_rows, column_override: note_cols) unless dry_run

  # Revisions
  rev_cols = %w[id note_id revision_kind content_markdown content_plain properties_data
                base_revision_id author_id ai_generated change_summary created_at updated_at]
  rev_rows = state["revisions"].map do |r|
    h = rev_cols.each_with_object({}) { |c, hash| hash[c] = r[c] }
    h["ai_generated"] = (r["ai_generated"] == true)
    h
  end
  puts "note_revisions: #{rev_rows.size}"
  insert_many(conn, "note_revisions", rev_rows, column_override: rev_cols) unless dry_run

  # Now set head_revision_id on notes
  puts "setting head_revision_id on notes..."
  state["notes"].each_slice(200) do |batch|
    batch.each do |n|
      head = n["head_revision_id"]
      next unless head
      unless dry_run
        conn.execute("UPDATE notes SET head_revision_id = #{conn.quote(head)} WHERE id = #{conn.quote(n['id'])}")
      end
    end
  end

  # note_tags
  nt_cols = %w[note_id tag_id created_at]
  nt_rows = state["note_tags"].map { |r| nt_cols.each_with_object({}) { |c, h| h[c] = r[c] } }
  puts "note_tags: #{nt_rows.size}"
  insert_many(conn, "note_tags", nt_rows, column_override: nt_cols) unless dry_run

  # note_links
  nl_cols = %w[src_note_id dst_note_id hier_role active context created_in_revision_id created_at updated_at]
  nl_rows = state["note_links"].map do |r|
    h = nl_cols.each_with_object({}) { |c, hash| hash[c] = r[c] }
    h["active"] = (r["active"] == true || r["active"] == 1)
    h
  end
  puts "note_links: #{nl_rows.size}"
  insert_many(conn, "note_links", nl_rows, column_override: nl_cols) unless dry_run

  # note_aliases (column is 'name', not 'alias')
  na_cols = %w[note_id name created_at updated_at]
  na_rows = state["note_aliases"].map { |r| na_cols.each_with_object({}) { |c, h| h[c] = r[c] } }
  puts "note_aliases: #{na_rows.size}"
  insert_many(conn, "note_aliases", na_rows, column_override: na_cols) unless dry_run

  # slug_redirects
  sr_cols = %w[note_id slug created_at updated_at]
  sr_rows = state["slug_redirects"].map { |r| sr_cols.each_with_object({}) { |c, h| h[c] = r[c] } }
  puts "slug_redirects: #{sr_rows.size}"
  insert_many(conn, "slug_redirects", sr_rows, column_override: sr_cols) unless dry_run

  if dry_run
    puts "\n(dry-run: rolling back)"
    raise ActiveRecord::Rollback
  end
end

puts "\n=== restore complete ==="
puts "notes:     #{conn.select_value('SELECT COUNT(*) FROM notes')}"
puts "revisions: #{conn.select_value('SELECT COUNT(*) FROM note_revisions')}"
puts "tags:      #{conn.select_value('SELECT COUNT(*) FROM tags')}"
puts "note_tags: #{conn.select_value('SELECT COUNT(*) FROM note_tags')}"
puts "note_links:#{conn.select_value('SELECT COUNT(*) FROM note_links')}"
