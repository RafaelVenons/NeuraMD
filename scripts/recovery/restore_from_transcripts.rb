#!/usr/bin/env ruby
# Rails runner: restore notes harvested from Claude Code session transcripts.
# Input: tmp/recovery/transcripts.jsonl (produced by scan_transcripts.rb).
#
# Strategy:
#   * For each harvested slug that is NOT already in the DB:
#     - If source is read_note/update_note/create_note (priority >= 4): create
#       the note with the full body we captured. Tag `recovered-2026-04-21-transcript`.
#     - Else (search_notes snippet / notes_by_tag snippet): create a placeholder
#       note containing the snippet + a banner flagging it as a stub. Tag
#       `recovered-2026-04-21-snippet` so the user can triage quickly.
#
# All recovered notes go through Notes::CheckpointService so they get a real
# revision + link graph sync. Tags `recovered-2026-04-21-transcript` and
# `recovered-2026-04-21-snippet` are created on the fly.
#
# Dry-run: rails runner scripts/recovery/restore_from_transcripts.rb -- --dry-run

require "json"
require "set"
require "securerandom"

dry_run = ARGV.include?("--dry-run")

DEFAULT_AUTHOR_ID = "bc73b56a-4234-47b5-804c-3c3e8515d4a5".freeze
INPUT = "tmp/recovery/transcripts.jsonl".freeze
RICH_SOURCES = %w[
  mcp__neuramd__read_note
  mcp__neuramd__update_note
  mcp__neuramd__create_note
  mcp__neuramd__patch_note
].to_set.freeze

author = User.find_by(id: DEFAULT_AUTHOR_ID) || User.first
raise "no user available" unless author
puts "using author: #{author.email} (#{author.id})"

existing_slugs = Note.pluck(:slug).to_set
puts "existing notes in DB: #{existing_slugs.size}"

records = []
File.foreach(INPUT) do |line|
  r = JSON.parse(line)
  next if existing_slugs.include?(r["slug"])
  records << r
end
rich = records.select { |r| RICH_SOURCES.include?(r["source"]) && r["body"].to_s.bytesize > 250 }
snippets = records - rich
puts "to restore: rich=#{rich.size}  snippet-only=#{snippets.size}"

def normalize_tags(raw)
  return [] if raw.nil?
  list = raw.is_a?(Array) ? raw : raw.to_s.split(",")
  list.map { |t| t.to_s.strip }.reject(&:empty?).uniq
end

def ensure_tag!(name, color: "#ff6b6b")
  Tag.find_or_create_by!(name: name) do |t|
    t.color_hex = color
    t.tag_scope = "note"
  end
end

restored_rich = 0
restored_snippet = 0
failed = []

ActiveRecord::Base.transaction do
  transcript_tag = ensure_tag!("recovered-2026-04-21-transcript")
  snippet_tag = ensure_tag!("recovered-2026-04-21-snippet")

  (rich + snippets).each do |r|
    slug = r["slug"]
    next if Note.exists?(slug: slug)

    is_rich = RICH_SOURCES.include?(r["source"]) && r["body"].to_s.bytesize > 250
    title = r["title"].to_s.strip
    title = slug.tr("-", " ").capitalize if title.empty?
    title = title[0..200]

    body = r["body"].to_s
    if !is_rich
      # Build a placeholder body from the snippet
      body = <<~MD
        > **Nota recuperada de snippet** — só temos excerto curto do acervo antigo. Conteúdo precisa ser reconstruído.

        ## Excerto preservado

        #{body}
      MD
    end

    begin
      ActiveRecord::Base.transaction(requires_new: true) do
        note = Note.new(slug: slug, title: title, note_kind: "markdown")
        note.save!

        tag_names = normalize_tags(r["tags"])
        tag_names << (is_rich ? "recovered-2026-04-21-transcript" : "recovered-2026-04-21-snippet")
        tag_names.uniq.each do |tn|
          tag = Tag.find_or_create_by!(name: tn) do |t|
            t.color_hex = "#888888"
            t.tag_scope = "note"
          end
          NoteTag.find_or_create_by!(note_id: note.id, tag_id: tag.id)
        end

        aliases = r["aliases"]
        if aliases.is_a?(Array)
          aliases.each do |a|
            next unless a.is_a?(String) && !a.strip.empty?
            NoteAlias.find_or_create_by!(note_id: note.id, name: a.strip)
          end
        end

        ::Notes::CheckpointService.call(note: note, content: body, author: author)
      end
      is_rich ? restored_rich += 1 : restored_snippet += 1
    rescue => e
      failed << [slug, e.class.name, e.message[0..120]]
    end
  end

  puts ""
  puts "=== summary ==="
  puts "  rich-body restored:    #{restored_rich}"
  puts "  snippet placeholders:  #{restored_snippet}"
  puts "  failed:                #{failed.size}"
  failed.first(10).each { |s, c, m| puts "    #{s} — #{c}: #{m}" }

  if dry_run
    puts "\n(dry-run: rolling back)"
    raise ActiveRecord::Rollback
  end
end

puts "\nfinal counts:"
puts "  notes:     #{Note.count}"
puts "  revisions: #{NoteRevision.count}"
puts "  recovered-2026-04-21-transcript: #{Tag.find_by(name: 'recovered-2026-04-21-transcript')&.notes&.count || 0}"
puts "  recovered-2026-04-21-snippet:    #{Tag.find_by(name: 'recovered-2026-04-21-snippet')&.notes&.count || 0}"
