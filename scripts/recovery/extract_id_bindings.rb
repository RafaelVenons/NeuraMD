#!/usr/bin/env ruby
# Pass 2: scan logs for identity bindings that are NOT in the INSERT stream.
# Rails uses PG default-generated uuids, so INSERT INTO foo (...) VALUES (...)
# RETURNING "id" never carries the uuid in the value list. We recover it from:
#
#   - `[DomainEvent] neuramd.note.created: {:note_id=>"uuid", :slug=>"slug"}`
#   - `WHERE "notes"."id" = 'uuid' AND LOWER("notes"."slug") = LOWER('slug')`
#   - `UPDATE "notes" SET "head_revision_id" = 'rev_uuid' ... WHERE "notes"."id" = 'note_uuid'`
#       (ties a freshly-inserted note_revision to its note)
#   - `INSERT INTO "note_tags" (...) VALUES (..., 'note_uuid', ..., 'tag_uuid', ...)`
#       (note_tags carry both foreign keys in the values list — we extract
#        those anyway, but this pass also associates tag_uuid -> name
#        via a preceding `INSERT INTO "tags"` slug lookup.)
#
# Emits JSONL events on stdout.

require "json"

$stdout.sync = true

ANSI_RE = /\e\[[0-9;]*m/

DOMAIN_EVENT_RE = /\[DomainEvent\] neuramd\.note\.created: \{:note_id=>"([0-9a-f-]{36})", :slug=>"([^"]+)"/
NOTE_ID_SLUG_RE = /"notes"\."id"\s*(?:!=|=)\s*'([0-9a-f-]{36})'\s+AND\s+LOWER\("notes"\."slug"\)\s*=\s*LOWER\('([^']+)'\)/
NOTE_HEAD_REV_RE = /UPDATE\s+"notes"\s+SET\s+"head_revision_id"\s*=\s*'([0-9a-f-]{36})'(?:,\s*"updated_at"\s*=\s*'([^']+)')?\s+WHERE\s+"notes"\."id"\s*=\s*'([0-9a-f-]{36})'/
# variant where updated_at comes first
NOTE_HEAD_REV_RE2 = /UPDATE\s+"notes"\s+SET\s+.*?"head_revision_id"\s*=\s*'([0-9a-f-]{36})'.*?WHERE\s+"notes"\."id"\s*=\s*'([0-9a-f-]{36})'/

# Tag INSERT: capture the tag name then on RETURNING we don't know the uuid.
# But subsequent NoteTag INSERT has (note_id, tag_id). We later map tag_id to
# name via the closest "SELECT" that joins tags by name, OR via
# `INSERT INTO "tags" ... VALUES (..., 'name', ...)` + the next log line
# `Tag Load (...) SELECT ... WHERE "tags"."name" = '...' LIMIT 1` which
# precedes the INSERT. Simpler: Tag's slug/name maps 1:1 to the tag row.
TAG_INSERT_RE = /INSERT\s+INTO\s+"tags"\s*\(([^)]+)\)\s*VALUES\s*\(([^)]+)\)/
TAG_SELECT_BY_NAME_RE = /"tags"\."id"\s*=\s*'([0-9a-f-]{36})'\s+AND\s+"tags"\."name"\s*=\s*'([^']+)'/
TAG_ID_NAME_LOAD_RE = /SELECT\s+"tags"\.\*\s+FROM\s+"tags"\s+WHERE\s+"tags"\."name"\s*=\s*'([^']+)'\s+LIMIT\s+1/
# After a Tag Create with RETURNING "id", the next attach is:
#   SELECT "note_tags".* FROM "note_tags" WHERE ..."tag_id" = 'uuid' LIMIT 1
# So we can't infer name from there. Better: Tag Insert order == creation
# order, and tag order == INSERT order in the parsed event stream. We pair
# by position below.

# Pending-revision tracking: when we see INSERT INTO "note_revisions" with
# note_id = N, we remember (timestamp, note_id). When the next
# `UPDATE "notes" SET "head_revision_id"=R WHERE id=N` appears, we bind R
# to the pending revision slot.
NOTE_REVISION_INSERT_NOTE_ID_RE = /INSERT\s+INTO\s+"note_revisions".+?'(?:checkpoint|draft)',\s*'([^']+)',\s*'(\{\})'/
# Simpler: scan for note_id after 'checkpoint'/'draft' is fragile. Use the
# fact that note_id is the second-to-last JSON-free string in the values
# list, but we already have full INSERT events in events.jsonl. Here we
# just track the UPDATE side.

# Pair notes INSERT with following note_revisions INSERT: both appear in the
# same request/transaction (Rails Note Create → NoteRevision Create). The
# revision's note_id is the note's id.
NOTE_CREATE_RE = /INSERT\s+INTO\s+"notes"\s*\(([^)]+)\)\s*VALUES\s*\(([^)]+)\)/
REVISION_CREATE_NOTE_ID_RE = /INSERT\s+INTO\s+"note_revisions".+VALUES\s*\(\s*(?:FALSE|TRUE),\s*(?:NULL|'[^']*'),\s*(?:NULL|'([0-9a-f-]{36})'),\s*(?:NULL|'[^']*(?:''[^']*)*'),\s*'[^']*',\s*'[^']*(?:''[^']*)*',\s*'[^']*',\s*'([0-9a-f-]{36})'/m

def extract_slug_from_note_insert(cols_src, vals_src)
  cols = cols_src.scan(/"([^"]+)"/).flatten
  slug_idx = cols.index("slug")
  return nil unless slug_idx
  # scan value tokens respecting quoted strings
  vals = []
  i = 0
  n = vals_src.length
  cur = +""
  in_str = false
  while i < n
    c = vals_src[i]
    if c == "'"
      if in_str
        if vals_src[i + 1] == "'"
          cur << "'"; i += 2; next
        else
          vals << cur.dup
          cur.clear
          in_str = false
        end
      else
        in_str = true
      end
    elsif in_str
      cur << c
    elsif c == ","
      # nothing
    end
    i += 1
  end
  vals[slug_idx]
end

files = ARGV.empty? ? ["log/development.log.0", "log/development.log"] : ARGV

pending_slug = nil

files.each do |path|
  next unless File.exist?(path)
  warn "scanning #{path}"
  File.foreach(path) do |raw_line|
    line = raw_line.gsub(ANSI_RE, "")

    if (m = line.match(DOMAIN_EVENT_RE))
      puts JSON.generate({type: "bind_note", id: m[1], slug: m[2], source: "domain_event"})
      next
    end

    if (m = line.match(NOTE_ID_SLUG_RE))
      puts JSON.generate({type: "bind_note", id: m[1], slug: m[2], source: "where_clause"})
    end

    # Track notes INSERT for sequential pairing
    if (m = line.match(NOTE_CREATE_RE))
      slug = extract_slug_from_note_insert(m[1], m[2])
      pending_slug = slug if slug
    end

    # note_revisions INSERT: has note_id in values; pair with pending_slug
    if pending_slug && line.include?('INSERT INTO "note_revisions"')
      # extract note_id: it's the 8th value (ai_generated, author_id, base_revision_id, change_summary, content_markdown, content_plain, created_at, note_id, ...)
      # Use simpler scan: find the first UUID after 'checkpoint'|'draft' literal — wait, that's after note_id
      # Best: scan the values section for UUIDs and take one that isn't base_revision_id
      m2 = line.match(/VALUES\s*\((.+)\)\s*RETURNING/)
      if m2
        uuids = m2[1].scan(/'([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})'/).flatten
        # values order: ai_generated, author_id, base_revision_id, change_summary, content_markdown, content_plain, created_at, note_id, revision_kind, updated_at, properties_data
        # UUIDs in there: [base_revision_id?, author_id?, note_id]. Heuristic: last UUID before 'checkpoint'|'draft' is note_id.
        note_id_match = m2[1].match(/'([0-9a-f-]{36})',\s*'(?:checkpoint|draft)'/)
        if note_id_match
          note_id = note_id_match[1]
          puts JSON.generate({type: "bind_note", id: note_id, slug: pending_slug, source: "note_revision_pair"})
          pending_slug = nil
        end
      end
    end

    if (m = line.match(NOTE_HEAD_REV_RE))
      puts JSON.generate({type: "bind_head_revision", revision_id: m[1], updated_at: m[2], note_id: m[3]})
    elsif (m = line.match(NOTE_HEAD_REV_RE2))
      puts JSON.generate({type: "bind_head_revision", revision_id: m[1], updated_at: nil, note_id: m[2]})
    end

    if (m = line.match(TAG_SELECT_BY_NAME_RE))
      puts JSON.generate({type: "bind_tag", id: m[1], name: m[2]})
    end
  end
end
