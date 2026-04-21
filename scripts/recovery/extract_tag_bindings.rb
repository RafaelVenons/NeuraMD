#!/usr/bin/env ruby
# Pair `Tag Create INSERT INTO "tags" ... VALUES (..., 'name', ...)` with the
# *next* `INSERT INTO "note_tags" (..., 'note_id', ..., 'tag_id')` in the log.
# In the `find_or_create_by(name: X); note.tags << tag` flow, these are emitted
# back-to-back in a single controller action, so the pairing is deterministic.
#
# Emits {type: "bind_tag", id: "<uuid>", name: "<name>"} JSONL on stdout.

require "json"

$stdout.sync = true

ANSI_RE = /\e\[[0-9;]*m/
TAG_CREATE_RE = /INSERT\s+INTO\s+"tags"\s*\(([^)]+)\)\s*VALUES\s*\(([^)]+)\)/
NOTE_TAG_CREATE_RE = /INSERT\s+INTO\s+"note_tags"\s*\(([^)]+)\)\s*VALUES\s*\(([^)]+)\)/

def extract_values(values_src)
  # naive: scan for quoted strings, NULL, bare words
  values_src.scan(/'((?:[^']|'')*)'|\b(NULL|TRUE|FALSE)\b/).map { |a, b|
    if a
      a.gsub("''", "'")
    else
      case b
      when "NULL" then nil
      when "TRUE" then true
      when "FALSE" then false
      end
    end
  }
end

def columns(cols_src)
  cols_src.scan(/"([^"]+)"/).flatten
end

files = ARGV.empty? ? ["log/development.log.0", "log/development.log"] : ARGV

pending_tag_name = nil
seen = {} # name -> id (for dedup)

files.each do |path|
  next unless File.exist?(path)
  warn "scanning #{path}"
  File.foreach(path) do |raw_line|
    line = raw_line.gsub(ANSI_RE, "")

    if (m = line.match(TAG_CREATE_RE))
      cols = columns(m[1])
      vals = extract_values(m[2])
      name_idx = cols.index("name")
      if name_idx && vals[name_idx]
        pending_tag_name = vals[name_idx]
      end
      next
    end

    if pending_tag_name && (m = line.match(NOTE_TAG_CREATE_RE))
      cols = columns(m[1])
      vals = extract_values(m[2])
      tag_idx = cols.index("tag_id")
      if tag_idx && vals[tag_idx]
        tag_id = vals[tag_idx]
        unless seen[pending_tag_name] == tag_id
          seen[pending_tag_name] = tag_id
          puts JSON.generate({type: "bind_tag", id: tag_id, name: pending_tag_name, source: "create_attach_pair"})
        end
        pending_tag_name = nil
      end
    end
  end
end

warn "bound #{seen.size} tag names to uuids"
