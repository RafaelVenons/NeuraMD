# frozen_string_literal: true

namespace :mcp do
  namespace :tokens do
    desc "Issue an MCP gateway token. Args: NAME, SCOPES (csv, default: read), AGENT_SLUG (optional)"
    task issue: :environment do
      name = ENV["NAME"].to_s.strip
      abort("usage: NAME=label SCOPES=read,write [AGENT_SLUG=foo-bot] bin/rails mcp:tokens:issue") if name.empty?

      scopes = ENV.fetch("SCOPES", "read").split(",").map(&:strip).reject(&:empty?)

      agent_slug = ENV["AGENT_SLUG"].to_s.strip
      agent_note_id = nil
      if agent_slug.present?
        note = Note.find_by(slug: agent_slug)
        abort("AGENT_SLUG #{agent_slug.inspect} not found") if note.nil?
        agent_note_id = note.id
      end

      result = McpAccessToken.issue!(name: name, scopes: scopes, agent_note_id: agent_note_id)

      puts "Issued token #{result.record.id} (#{name}) — scopes: #{scopes.join(",")}"
      if result.record.agent_note
        puts "Bound to agent note: #{result.record.agent_note.slug} (#{result.record.agent_note.title})"
      end
      puts "Plaintext (store now — not recoverable):"
      puts result.plaintext
    end

    desc "Revoke an MCP gateway token by id"
    task revoke: :environment do
      id = ENV["ID"].to_s.strip
      abort("usage: ID=<uuid> bin/rails mcp:tokens:revoke") if id.empty?

      token = McpAccessToken.find(id)
      token.update!(revoked_at: Time.current)
      puts "Revoked #{token.id} (#{token.name})"
    end

    desc "List MCP gateway tokens"
    task list: :environment do
      McpAccessToken.order(created_at: :desc).each do |t|
        status = t.revoked? ? "REVOKED" : "active"
        last = t.last_used_at&.iso8601 || "never"
        puts "#{t.id}  #{status.ljust(8)}  scopes=#{t.scopes.join(",")}  last_used=#{last}  name=#{t.name}"
      end
    end
  end
end
