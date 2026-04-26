#!/usr/bin/env ruby
# Standalone parser for the post-receive hook's validator wake-up
# extension. No Rails dependency — runs as a one-shot subprocess
# during deploy, so it must boot in <50ms and avoid touching the
# bundle (the deploy host loads gems lazily and the hook runs
# before bundle install on first deploy).
#
# Two CLI modes, both stdin -> stdout:
#
#   parse-pr-number  — reads a git commit message, prints the PR
#                      number from its subject (squash-merge
#                      "(#42)" tail or merge-commit
#                      "Merge pull request #42 from ..." prefix).
#                      Exits 1 with no output when no number found.
#
#   parse-slugs      — reads a markdown PR body, prints one slug
#                      per line from the "## Validar pós-deploy
#                      com:" section. Slugs are deduped and capped
#                      at SLUG_LIMIT to bound the wake budget.
#                      Exits 0 with no output when the section
#                      is absent or empty.
module ValidatorSlugs
  SLUG_LIMIT = 10
  # Ruby's /i flag does not case-fold reliably for accented Latin
  # characters, so the óÓoO class is enumerated explicitly. Header
  # accepts the accented and unaccented form, any casing.
  HEADER_PATTERN = /\A##\s+Validar\s+p[óÓoO]s[-\s]deploy\s+com:?\s*\z/i
  SECTION_END_PATTERN = /\A\#{1,2}\s/
  SLUG_PATTERN = /\A\s*[-*]\s+`?([a-z][a-z0-9\-]*[a-z0-9])`?(?:\s|—|$)/
  PR_NUMBER_TAIL_PATTERN = /\(#(\d+)\)\s*\z/
  PR_NUMBER_MERGE_PATTERN = /\AMerge\s+pull\s+request\s+#(\d+)\s+from\s+/

  module_function

  # Returns Integer PR number or nil. Inspects only the commit
  # subject (first line) — bodies frequently mention unrelated PRs.
  def parse_pr_number(message)
    return nil if message.nil? || message.empty?
    subject = message.lines.first.to_s.chomp
    if (m = PR_NUMBER_TAIL_PATTERN.match(subject))
      return Integer(m[1])
    end
    if (m = PR_NUMBER_MERGE_PATTERN.match(subject))
      return Integer(m[1])
    end
    nil
  end

  # Returns Array<String> of unique slugs in document order, capped
  # at SLUG_LIMIT. Returns [] when the section header is missing or
  # the section contains no parseable bullets.
  def parse_slugs(body)
    return [] if body.nil? || body.empty?

    in_section = false
    slugs = []
    body.each_line do |raw_line|
      line = raw_line.chomp
      if HEADER_PATTERN.match?(line)
        in_section = true
        next
      end
      next unless in_section
      # Any new heading at H1/H2 ends the section. H3+ stay inside.
      break if SECTION_END_PATTERN.match?(line) && !line.start_with?("###")
      if (m = SLUG_PATTERN.match(line))
        slug = m[1]
        slugs << slug unless slugs.include?(slug)
        break if slugs.length >= SLUG_LIMIT
      end
    end
    slugs
  end
end

if $PROGRAM_NAME == __FILE__
  case ARGV.shift
  when "parse-pr-number"
    n = ValidatorSlugs.parse_pr_number($stdin.read)
    if n
      puts n
      exit 0
    else
      exit 1
    end
  when "parse-slugs"
    ValidatorSlugs.parse_slugs($stdin.read).each { |s| puts s }
    exit 0
  else
    warn "usage: validator_slugs.rb {parse-pr-number|parse-slugs}"
    exit 2
  end
end
