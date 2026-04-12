# frozen_string_literal: true

# Dry-run CLI for the new TOC-driven import pipeline. Runs convert → sanitize
# → toc_detect → heading_match → density_plan and prints a report. Creates NO
# notes. Usage:
#
#   bin/test-import PATH [--threshold=N] [--save-markdown] [--pattern=<glob>]
#
# Multiple paths or a directory are supported; passing a directory scans *.pdf.
namespace :import do
  desc "Dry-run the new TOC-driven import pipeline against a file or directory"
  task :test, [:path, :threshold] => :environment do |_, args|
    path = args[:path].presence || ENV["IMPORT_TEST_PATH"].presence
    threshold = (args[:threshold].presence || ENV.fetch("THRESHOLD", "30")).to_i
    save_markdown = ENV["SAVE_MARKDOWN"].present?
    pattern = ENV["PATTERN"].presence || "**/*.pdf"

    unless path
      puts "Usage: bin/test-import PATH [THRESHOLD] [SAVE_MARKDOWN=1]"
      exit(1)
    end

    paths =
      if File.directory?(path)
        Dir.glob(File.join(path, pattern))
      else
        [path]
      end

    if paths.empty?
      puts "no files found at #{path}"
      exit(1)
    end

    puts "=" * 72
    puts "Dry-run: TOC-driven import pipeline"
    puts "Threshold: #{threshold} density-lines per note"
    puts "Files:     #{paths.size}"
    puts "=" * 72

    paths.each { |p| Importer::DryRun.report(p, threshold: threshold, save_markdown: save_markdown) }
  end
end

module Importer
  # Runs the full dry-run pipeline for a single file and prints the report.
  module DryRun
    module_function

    def report(path, threshold:, save_markdown:)
      puts
      puts "── #{File.basename(path)} ".ljust(72, "─")
      start = Time.current

      begin
        raw, cache_hit = fetch_or_convert(path)
      rescue FileImports::ConvertService::ConversionError => e
        puts "  convert FAILED: #{e.message}"
        return
      end

      convert_ms = ((Time.current - start) * 1000).to_i
      source = cache_hit ? "cache" : "pymupdf4llm"
      puts "  convert:  #{convert_ms}ms (#{source}), #{raw.lines.size} lines, #{raw.bytesize} bytes"

      report = FileImports::SanitizeService.call(markdown: raw, filename: File.basename(path))
      if report.usable
        puts "  sanitize: #{report.applied.size} transforms, #{report.warnings.size} warnings"
      else
        puts "  sanitize REJECTED: #{report.warnings.first}"
        return
      end
      markdown = report.markdown

      if save_markdown
        out_path = "/tmp/#{File.basename(path, '.*')}.sanitized.md"
        File.write(out_path, markdown)
        puts "  saved:    #{out_path}"
      end

      toc = FileImports::TocDetector.call(markdown: markdown)
      if toc.nil?
        puts "  TOC:      NOT DETECTED → would import as single note"
        return
      end

      puts "  TOC:      anchor='#{toc[:anchor_kind]}' line=#{toc[:anchor_line]}, #{toc[:entries].size} entries"
      dump_level_breakdown(toc[:entries])
      dump_entries_preview(toc[:entries])

      matched = FileImports::HeadingMatcher.call(
        markdown: markdown, entries: toc[:entries], skip_before_line: toc[:anchor_line]
      )
      matches = matched.count { |m| m[:body_line] }
      pct = matches.to_f / matched.size * 100
      puts "  match:    #{matches}/#{matched.size} (#{pct.round(1)}%) body headings"
      dump_unmatched(matched)

      if pct < 50.0
        puts "  ⚠ low match rate — would fall back to single note"
        return
      end

      plan = FileImports::DensityPlanner.call(
        markdown: markdown, matched_entries: matched,
        root_title: derive_root_title(path), threshold: threshold
      )

      s = plan[:stats]
      puts "  plan:     split=#{s[:split_count]} merged=#{s[:merged_count]} blocklisted=#{s[:blocklisted_count]} → #{s[:total_notes]} total notes"
      dump_tree(plan[:main], 2)
    end

    def dump_level_breakdown(entries)
      by_level = entries.group_by(&:level).sort.to_h
      by_level.each do |lvl, es|
        puts "    └ level #{lvl}: #{es.size}"
      end
    end

    def dump_entries_preview(entries, limit: 6)
      puts "    first entries:"
      entries.first(limit).each do |e|
        prefix = "  " * e.level
        num = e.number ? "#{e.number} " : ""
        puts "      #{prefix}#{num}#{e.title} (p.#{e.page || '?'})"
      end
      puts "      … +#{entries.size - limit} more" if entries.size > limit
    end

    def dump_unmatched(matched, limit: 5)
      unmatched = matched.reject { |m| m[:body_line] }
      return if unmatched.empty?
      puts "    unmatched (#{unmatched.size}):"
      unmatched.first(limit).each do |m|
        puts "      - #{m[:number] || '—'} #{m[:title]}"
      end
      puts "      … +#{unmatched.size - limit} more" if unmatched.size > limit
    end

    def dump_tree(node, indent, depth: 0)
      return if depth > 2  # don't print every leaf
      prefix = " " * indent
      label = node[:title].truncate(60)
      density = node[:density]
      children = node[:children] || []
      if depth.zero?
        puts "#{prefix}📘 #{label} [#{density} lines, #{children.size} children]"
      else
        puts "#{prefix}└ #{label} [#{density} lines, #{children.size} children]"
      end
      children.first(8).each { |c| dump_tree(c, indent + 2, depth: depth + 1) }
      puts "#{prefix}  … +#{children.size - 8} more children" if children.size > 8
    end

    def derive_root_title(path)
      File.basename(path, File.extname(path)).tr("_-", " ").strip
    end

    CACHE_DIR = "/tmp/import-cache"

    def fetch_or_convert(path)
      FileUtils.mkdir_p(CACHE_DIR)
      stat = File.stat(path)
      key = Digest::SHA256.hexdigest("#{File.expand_path(path)}|#{stat.size}|#{stat.mtime.to_i}")
      cache_path = File.join(CACHE_DIR, "#{key}.md")
      if ENV["NO_CACHE"].blank? && File.exist?(cache_path)
        return [File.read(cache_path), true]
      end
      markdown = FileImports::ConvertService.call(file_path: path)
      File.write(cache_path, markdown)
      # Also mirror to /tmp/<basename>.md for easy inspection.
      inspect_path = "/tmp/#{File.basename(path, '.*')}.md"
      File.write(inspect_path, markdown)
      [markdown, false]
    end
  end
end
