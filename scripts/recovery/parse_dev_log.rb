#!/usr/bin/env ruby
# Extract INSERT/UPDATE/DELETE rows for restorable tables from Rails dev log.
# Emits one JSON event per line (stdout) ordered as they appear in the logs.
#
# Usage:
#   ruby scripts/recovery/parse_dev_log.rb log/development.log.0 log/development.log > tmp/recovery/events.jsonl

require "json"

$stdout.sync = true
$stderr.sync = true

TABLES = %w[
  notes note_revisions tags note_tags note_aliases note_links
  note_properties property_definitions users slug_redirects
  mention_exclusions link_tags note_views note_headings note_blocks
  agent_messages tentacle_cron_states
].freeze
TABLES_SET = TABLES.to_set

require "set"

ANSI_RE = /\e\[[0-9;]*m/
FAST_FILTER = /INSERT INTO "|UPDATE "|DELETE FROM "/
TOKEN_RE = /
  ( '(?:[^']|'')*' )          # 1: quoted string
  | ( NULL | TRUE | FALSE )   # 2: literal
  | ( -?\d+(?:\.\d+)? )       # 3: number
/ix

def unquote(token)
  token[1..-2].gsub("''", "'")
end

def token_to_value(m)
  if m[0]     then unquote(m[0])
  elsif m[1]  then case m[1].upcase
                   when "NULL"  then nil
                   when "TRUE"  then true
                   when "FALSE" then false
                   end
  elsif m[2]  then (m[2].include?(".") ? m[2].to_f : m[2].to_i)
  end
end

def scan_values(src)
  vals = []
  src.scan(TOKEN_RE) { |a, b, c| vals << token_to_value([a, b, c]) }
  vals
end

def parse_insert(sql)
  # header: INSERT INTO "tbl" ("c1", "c2", ...) VALUES (
  m = sql.match(/INSERT\s+INTO\s+"([^"]+)"\s*\(([^)]*)\)\s*VALUES\s*\(/i)
  return nil unless m
  table = m[1]
  cols = m[2].scan(/"([^"]+)"/).flatten
  tail = sql[m.end(0)..]  # everything after the opening `(`
  values = scan_values(tail)
  values = values.first(cols.length)  # drop trailing RETURNING-"id" or comment literals if any
  {op: "insert", table: table, columns: cols, values: values}
end

def parse_update(sql)
  m = sql.match(/UPDATE\s+"([^"]+)"\s+SET\s+/i)
  return nil unless m
  table = m[1]
  rest = sql[m.end(0)..]
  # Find WHERE at depth 0 in rest (no nested strings). Use regex with scan that skips strings.
  # Simpler: split on the last WHERE outside strings. Use a regex that finds WHERE preceded by non-string.
  where_split = split_on_unquoted_where(rest)
  return nil unless where_split
  set_src, where_src = where_split

  sets = {}
  set_src.scan(/"([^"]+)"\s*=\s*(#{TOKEN_RE.source})/xm) do |col, _a, strv, litv, numv|
    sets[col] = token_to_value([strv, litv, numv])
  end

  where = {}
  where_src.scan(/"([^"]+)"\s*=\s*(#{TOKEN_RE.source})/xm) do |col, _a, strv, litv, numv|
    where[col] = token_to_value([strv, litv, numv])
  end

  {op: "update", table: table, set: sets, where: where}
end

def parse_delete(sql)
  m = sql.match(/DELETE\s+FROM\s+"([^"]+)"\s+WHERE\s+/i)
  return nil unless m
  table = m[1]
  rest = sql[m.end(0)..]
  where = {}
  rest.scan(/"([^"]+)"\s*=\s*(#{TOKEN_RE.source})/xm) do |col, _a, strv, litv, numv|
    where[col] = token_to_value([strv, litv, numv])
  end
  {op: "delete", table: table, where: where}
end

# Find WHERE keyword that is NOT inside a quoted string. Scan strings and
# consume them to get accurate position.
def split_on_unquoted_where(src)
  i = 0
  n = src.bytesize
  while i < n
    ch = src[i]
    if ch == "'"
      # consume string
      j = i + 1
      while j < n
        if src[j] == "'"
          if src[j + 1] == "'"
            j += 2
          else
            j += 1
            break
          end
        else
          j += 1
        end
      end
      i = j
    elsif src[i, 6] =~ /\AWHERE\s/i
      return [src[0...i], src[(i + 6)..]]
    else
      i += 1
    end
  end
  nil
end

# --- main loop -----------------------------------------------------------------
counts = Hash.new(0)
files = ARGV.empty? ? ["log/development.log.0", "log/development.log"] : ARGV

files.each do |path|
  next unless File.exist?(path)
  warn "parsing #{path} (#{File.size(path) / 1_048_576} MB)"
  line_no = 0
  File.foreach(path) do |raw_line|
    line_no += 1
    warn "  line #{line_no} events=#{counts.values.sum}" if (line_no % 50_000).zero?
    next unless raw_line.match?(FAST_FILTER)
    # cheap table-name check before any regex
    next unless TABLES.any? { |t| raw_line.include?(%("#{t}")) }
    sql = raw_line.gsub(ANSI_RE, "").strip

    event =
      if sql =~ /\AINSERT\s+INTO\s+"([^"]+)"/i && TABLES_SET.include?($1)
        parse_insert(sql)
      elsif sql =~ /\AUPDATE\s+"([^"]+)"/i && TABLES_SET.include?($1)
        parse_update(sql)
      elsif sql =~ /\ADELETE\s+FROM\s+"([^"]+)"/i && TABLES_SET.include?($1)
        parse_delete(sql)
      else
        # SQL might be prefixed by Rails log tags like "[ActiveJob] ... Note Create"
        # strip known prefix up to the real keyword
        if sql.sub!(/\A.*?(?=INSERT\s+INTO\s+"|UPDATE\s+"|DELETE\s+FROM\s+")/m, "")
          retry_event = (
            if sql =~ /\AINSERT/i then parse_insert(sql)
            elsif sql =~ /\AUPDATE/i then parse_update(sql)
            elsif sql =~ /\ADELETE/i then parse_delete(sql)
            end
          )
          retry_event
        end
      end

    next unless event
    next unless TABLES_SET.include?(event[:table])
    counts[[event[:op], event[:table]]] += 1
    puts JSON.generate(event)
  end
end

warn "\nevent counts:"
counts.sort.each { |(op, t), c| warn "  %-7s %-25s %6d" % [op, t, c] }
warn "total: #{counts.values.sum}"
