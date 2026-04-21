#!/usr/bin/env ruby
# Consolidate events.jsonl + bindings.jsonl + tag_bindings.jsonl into a single
# state.json that the restorer can replay directly.
#
# Cutoff: ignore events with created_at >= WIPE_CUTOFF (post-wipe noise).
#
# Strategy:
#   * notes:        id from bind_note[slug]. apply UPDATEs in order (title, slug, deleted_at, head_revision_id, updated_at).
#   * tags:         id from tag_bindings[name]. ignore tags that were never attached.
#   * revisions:    id from bind_head_revision by (note_id, created_at) match, else fabricate. keep only the latest per note as head; emit ALL in chronological order to preserve chain.
#   * note_tags:    (note_id, tag_id) set; apply delete events.
#   * note_links:   emit INSERT rows as-is (source, target, role, display_text). dedup on (source_id, target_id, role, display_text).
#   * note_aliases: emit INSERT rows. id not needed.
#   * slug_redirects: emit INSERT rows.
#   * users:        ignore user INSERTs from post-wipe; caller provides old user id (from revisions.author_id) and stitches identity.

require "json"
require "set"
require "securerandom"

WIPE_CUTOFF = "2026-04-21 11:00:00".freeze

events_path = ARGV[0] || "tmp/recovery/events.jsonl"
bindings_path = ARGV[1] || "tmp/recovery/bindings.jsonl"
tag_bindings_path = ARGV[2] || "tmp/recovery/tag_bindings.jsonl"
out_path = ARGV[3] || "tmp/recovery/state.json"

# --- load bindings ---
# Sequential queue: N-th note INSERT in log pairs with N-th domain_event bind.
# Slugs can repeat (deleted+recreated), so dict-by-slug loses data.
domain_event_queue = [] # [[slug, id], ...] in log order
note_id_to_head_revisions = Hash.new { |h, k| h[k] = [] } # note_id -> [{revision_id, updated_at}]
slug_id_where_bindings = {} # slug -> [ids] from WHERE-clause evidence
tag_name_to_id = {}

File.foreach(bindings_path) do |line|
  b = JSON.parse(line)
  case b["type"]
  when "bind_note"
    if b["source"] == "domain_event"
      domain_event_queue << [b["slug"], b["id"]]
    else
      (slug_id_where_bindings[b["slug"]] ||= []) << b["id"]
    end
  when "bind_head_revision"
    note_id_to_head_revisions[b["note_id"]] << {revision_id: b["revision_id"], updated_at: b["updated_at"]}
  end
end

File.foreach(tag_bindings_path) do |line|
  b = JSON.parse(line)
  tag_name_to_id[b["name"]] = b["id"]
end

warn "bindings: #{domain_event_queue.size} sequential notes, #{slug_id_where_bindings.size} WHERE-clause fallbacks, #{tag_name_to_id.size} tags, #{note_id_to_head_revisions.values.sum(&:size)} head-revision events across #{note_id_to_head_revisions.size} notes"

# Build a map of valid note_ids (all we ever saw)
all_note_ids = Set.new(domain_event_queue.map(&:last))
warn "total distinct note_ids from bindings: #{all_note_ids.size}"

# --- state ---
notes = {} # note_id -> cols hash
revisions_by_note = Hash.new { |h, k| h[k] = [] } # note_id -> [revision_hash]
tags = {} # tag_id -> cols hash
note_tags = {} # [note_id, tag_id] -> {created_at}
note_links = {} # [source_note_id, target_note_id, role, display_text, position] -> row
note_aliases = [] # [rows]
slug_redirects = [] # [rows]
property_definitions = [] # [{name, property_type, ...}]
note_properties = [] # [{note_id, property_definition_id (by name), value}] — resolve later

skipped_post_wipe = Hash.new(0)
skipped_missing_binding = Hash.new(0)

def event_created_at(e)
  d = if e["op"] == "insert" then Hash[e["columns"].zip(e["values"])]
  elsif e["op"] == "update" then e["set"] || {}
  elsif e["op"] == "delete" then e["where"] || {}
  end
  d["created_at"] || d["updated_at"]
end

# Track revision id → name mapping we'll need for property_definitions later (not done here)

File.foreach(events_path) do |line|
  e = JSON.parse(line)
  table = e["table"]

  # post-wipe filter
  ts = event_created_at(e)
  if ts && ts >= WIPE_CUTOFF
    skipped_post_wipe[[e["op"], table]] += 1
    next
  end

  case e["op"]
  when "insert"
    cols = e["columns"]
    vals = e["values"]
    d = Hash[cols.zip(vals)]
    case table
    when "notes"
      slug = d["slug"]
      # Pop next domain_event binding; assert slug match.
      bind = domain_event_queue.shift
      unless bind
        skipped_missing_binding[[e["op"], table]] += 1
        next
      end
      if bind.first != slug
        warn "WARN: note insert slug=#{slug.inspect} but next bind slug=#{bind.first.inspect} id=#{bind.last}; skipping mismatched pair"
        skipped_missing_binding[[e["op"], table]] += 1
        # push back — maybe log had interleaved ordering
        domain_event_queue.unshift(bind)
        next
      end
      nid = bind.last
      notes[nid] = d.merge("id" => nid)
    when "note_revisions"
      nid = d["note_id"]
      revisions_by_note[nid] << d
    when "tags"
      name = d["name"]
      tid = tag_name_to_id[name]
      unless tid
        skipped_missing_binding[[e["op"], table]] += 1
        next
      end
      tags[tid] ||= d.merge("id" => tid)
    when "note_tags"
      key = [d["note_id"], d["tag_id"]]
      note_tags[key] = d
    when "note_links"
      key = [d["src_note_id"], d["dst_note_id"], d["hier_role"]]
      note_links[key] = d
    when "note_aliases"
      note_aliases << d
    when "slug_redirects"
      slug_redirects << d
    when "property_definitions"
      property_definitions << d
    when "note_properties"
      note_properties << d
    end
  when "update"
    set = e["set"] || {}
    where = e["where"] || {}
    case table
    when "notes"
      nid = where["id"]
      next unless nid && notes[nid]
      notes[nid].merge!(set)
    when "note_revisions"
      # rare; most revisions are immutable
      # skip — we don't track revision id-in-state here easily
    end
  when "delete"
    where = e["where"] || {}
    case table
    when "note_tags"
      key = [where["note_id"], where["tag_id"]]
      note_tags.delete(key)
    when "notes"
      # hard delete? soft-delete is via UPDATE deleted_at
      nid = where["id"]
      notes.delete(nid) if nid
    end
  end
end

# Pick head revision per note: prefer latest bind_head_revision, else latest revision by created_at.
note_head_revision = {} # note_id -> revision_id
revisions_final = [] # flattened, with id assigned

revisions_by_note.each do |nid, revs|
  next if revs.empty?
  binds = note_id_to_head_revisions[nid] || []
  # sort revisions chronologically
  revs.sort_by! { |r| r["created_at"].to_s }

  # Assign revision_ids: try to match by created_at/updated_at to bind events.
  used_binds = Set.new
  revs.each do |r|
    # match by any bind where updated_at == revision.created_at (head_revision_id UPDATE happens in same tx as revision INSERT)
    match = binds.find { |b| !used_binds.include?(b[:revision_id]) && (b[:updated_at] == r["created_at"] || b[:updated_at].to_s.start_with?(r["created_at"].to_s[0..18])) }
    if match
      r["id"] = match[:revision_id]
      used_binds << match[:revision_id]
    else
      r["id"] = SecureRandom.uuid
      r["_fabricated_id"] = true
    end
  end

  # Head = latest revision's id
  head = revs.last
  note_head_revision[nid] = head["id"]
  revisions_final.concat(revs)
end

require "securerandom"

# Dedup notes by slug: slug is UNIQUE in DB, but the log contains prior
# import-cycle ghosts (user re-ran bin/import-notes, which hard-deletes then
# recreates with new uuid + same slug). Keep only the latest-created per slug.
slug_latest = {}
notes.each do |nid, n|
  slug = n["slug"]
  current = slug_latest[slug]
  if current.nil? || n["created_at"].to_s > current["created_at"].to_s
    slug_latest[slug] = n
  end
end
live_note_ids = Set.new(slug_latest.values.map { |n| n["id"] })
dropped = notes.size - live_note_ids.size
notes.reject! { |nid, _| !live_note_ids.include?(nid) }
warn "  dedup notes by slug: dropped #{dropped} ghost notes (from earlier import cycles)"

# Apply head_revision to notes
note_head_revision.each do |nid, rid|
  next unless notes[nid]
  notes[nid]["head_revision_id"] = rid
end

# Filter revisions attached to notes that exist in `notes`
revisions_final.select! { |r| notes.key?(r["note_id"]) }

# Filter note_tags/note_links/aliases/redirects to existing notes
note_tags.reject! { |(nid, tid), _| !notes.key?(nid) || !tags.key?(tid) }
note_links.reject! { |k, v| !notes.key?(v["src_note_id"]) || !notes.key?(v["dst_note_id"]) }
note_aliases.select! { |a| notes.key?(a["note_id"]) }
slug_redirects.select! { |r| notes.key?(r["note_id"]) }

# Drop revisions attached to ghost notes (already handled via notes.key? filter)
revisions_final.select! { |r| notes.key?(r["note_id"]) }

# Null out base_revision_id that points to a revision no longer in our set
valid_revision_ids = Set.new(revisions_final.map { |r| r["id"] })
orphan_base = 0
revisions_final.each do |r|
  if r["base_revision_id"] && !valid_revision_ids.include?(r["base_revision_id"])
    r["base_revision_id"] = nil
    orphan_base += 1
  end
end
warn "  nulled orphan base_revision_id: #{orphan_base}"

# Repoint note_links.created_in_revision_id to a valid revision when the
# original reference isn't in our restored set. Prefer the src note's head.
repointed = 0
note_links.each_value do |link|
  rid = link["created_in_revision_id"]
  next if rid && valid_revision_ids.include?(rid)
  # pick the source note's head revision
  head = note_head_revision[link["src_note_id"]] || note_head_revision[link["dst_note_id"]]
  if head
    link["created_in_revision_id"] = head
    repointed += 1
  else
    link["_drop"] = true
  end
end
note_links.reject! { |_, v| v["_drop"] }
warn "  repointed note_links created_in_revision_id: #{repointed}"

warn "\n=== consolidated state ==="
warn "  notes:              #{notes.size}"
warn "  revisions:          #{revisions_final.size} (fabricated ids: #{revisions_final.count { |r| r['_fabricated_id'] }})"
warn "  tags:               #{tags.size}"
warn "  note_tags:          #{note_tags.size}"
warn "  note_links:         #{note_links.size}"
warn "  note_aliases:       #{note_aliases.size}"
warn "  slug_redirects:     #{slug_redirects.size}"
warn "  property_defs:      #{property_definitions.size}"
warn "  note_properties:    #{note_properties.size}"
warn "\n=== skipped (post-wipe) ==="
skipped_post_wipe.sort.each { |(op, t), c| warn "  %-7s %-25s %d" % [op, t, c] }
warn "\n=== skipped (missing binding) ==="
skipped_missing_binding.sort.each { |(op, t), c| warn "  %-7s %-25s %d" % [op, t, c] }

state = {
  notes: notes.values,
  revisions: revisions_final,
  tags: tags.values,
  note_tags: note_tags.values,
  note_links: note_links.values,
  note_aliases: note_aliases,
  slug_redirects: slug_redirects,
  property_definitions: property_definitions,
  note_properties: note_properties,
  author_id_in_revisions: revisions_final.map { |r| r["author_id"] }.compact.uniq,
  cutoff_utc: WIPE_CUTOFF
}

File.write(out_path, JSON.generate(state))
warn "\nwrote #{out_path} (#{File.size(out_path) / 1024} KB)"
