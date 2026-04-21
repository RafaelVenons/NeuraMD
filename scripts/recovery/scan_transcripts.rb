#!/usr/bin/env ruby
# Scan Claude Code session transcripts for MCP tool results that contain
# note content. Emit JSONL records on stdout, one per distinct (slug, timestamp)
# observation. A later pass deduplicates by slug, keeping the latest observation.
#
# We harvest content from:
#   - mcp__neuramd__read_note         -> result contains full body/title/tags/links
#   - mcp__neuramd__create_note       -> input carries the content just created
#   - mcp__neuramd__update_note       -> input carries the full replacement body
#   - mcp__neuramd__patch_note        -> input is a diff; we record partial patches
#   - mcp__neuramd__search_notes      -> results list {slug, title, snippet} — weak evidence
#   - mcp__neuramd__import_markdown   -> input has raw markdown + base_tag
#
# Transcripts scanned: every .jsonl under ~/.claude/projects whose project
# directory references NeuraMD, sagetrembo, shopAI, octogent, or tentacles
# (those projects use the NeuraMD MCP and therefore cached note content).

require "json"

# All project dirs under ~/.claude/projects — several sibling projects also used
# the NeuraMD MCP and cached read_note results, so harvest across all of them.
ROOTS = Dir["/home/venom/.claude/projects/*"].select { |d| Dir.exist?(d) }

warn "scanning #{ROOTS.size} project dirs"

harvested_by_slug = {}

# Higher = richer. Prefer a full body from read_note/update_note/create_note
# over a 200-char snippet from search_notes/notes_by_tag.
SOURCE_PRIORITY = {
  "mcp__neuramd__read_note" => 5,
  "mcp__neuramd__update_note" => 4,
  "mcp__neuramd__create_note" => 4,
  "mcp__neuramd__patch_note" => 3,
  "mcp__neuramd__notes_by_tag" => 2,
  "mcp__neuramd__recent_changes" => 2,
  "mcp__neuramd__search_notes" => 1
}.freeze

def record(harvested, slug, source, timestamp, data)
  return unless slug && !slug.empty?
  prev = harvested[slug]
  new_priority = SOURCE_PRIORITY[source] || 0
  if prev.nil?
    harvested[slug] = {ts: timestamp, source: source, priority: new_priority, data: data}
    return
  end
  prev_priority = prev[:priority]
  if new_priority > prev_priority
    harvested[slug] = {ts: timestamp, source: source, priority: new_priority, data: data}
  elsif new_priority == prev_priority && timestamp.to_s > prev[:ts].to_s
    harvested[slug] = {ts: timestamp, source: source, priority: new_priority, data: data}
  end
end

ROOTS.each do |root|
  Dir["#{root}/**/*.jsonl"].each do |file|
    tool_use_by_id = {}
    File.foreach(file) do |line|
      begin
        m = JSON.parse(line)
      rescue JSON::ParserError
        next
      end
      ts = m["timestamp"] || m["created_at"]
      next unless m["message"]
      content = m["message"]["content"]
      next unless content.is_a?(Array)
      content.each do |c|
        case c["type"]
        when "tool_use"
          name = c["name"].to_s
          next unless name.start_with?("mcp__neuramd__")
          tool_use_by_id[c["id"]] = {name: name, input: c["input"], ts: ts}
          # harvest from inputs that carry content
          input = c["input"] || {}
          case name
          when "mcp__neuramd__create_note", "mcp__neuramd__update_note"
            slug = input["slug"] || input["new_slug"]
            body = input["content_markdown"] || input["content"]
            if slug && body
              record(harvested_by_slug, slug, name, ts, {
                slug: slug,
                title: input["title"],
                body: body,
                tags: input["tags"] || input["set_tags"],
                aliases: input["aliases"] || input["set_aliases"]
              })
            end
          when "mcp__neuramd__import_markdown"
            # skip — each heading becomes a note, handled via read_note later
          end
        when "tool_result"
          ref = tool_use_by_id[c["tool_use_id"]]
          next unless ref
          name = ref[:name]
          raw = c["content"]
          text = raw.is_a?(Array) ? raw.map { |x| x["text"] }.compact.join : raw.to_s
          next if text.empty?

          case name
          when "mcp__neuramd__read_note"
            begin
              obj = JSON.parse(text)
            rescue JSON::ParserError
              next
            end
            slug = obj["slug"]
            next unless slug
            record(harvested_by_slug, slug, name, ref[:ts], {
              slug: slug,
              title: obj["title"],
              body: obj["body"],
              tags: obj["tags"] || (obj["tags_inline"] || []),
              aliases: obj["aliases"],
              outgoing_links: obj["outgoing_links"],
              backlinks: obj["backlinks"]
            })
          when "mcp__neuramd__search_notes", "mcp__neuramd__notes_by_tag", "mcp__neuramd__recent_changes"
            # Each result: {slug, title, snippet} — weak content
            begin
              obj = JSON.parse(text)
            rescue JSON::ParserError
              next
            end
            list = obj.is_a?(Array) ? obj : (obj["results"] || obj["notes"] || [])
            next unless list.is_a?(Array)
            list.each do |r|
              next unless r.is_a?(Hash) && r["slug"]
              # Only record if we haven't seen richer content for this slug
              unless harvested_by_slug[r["slug"]]
                record(harvested_by_slug, r["slug"], name, ref[:ts], {
                  slug: r["slug"],
                  title: r["title"],
                  body: r["snippet"] || r["excerpt"],
                  tags: r["tags"]
                })
              end
            end
          end
        end
      end
    end
  end
end

warn "harvested unique slugs: #{harvested_by_slug.size}"

# emit JSONL
harvested_by_slug.each do |slug, rec|
  puts JSON.generate(slug: slug, ts: rec[:ts], source: rec[:source], **rec[:data])
end
