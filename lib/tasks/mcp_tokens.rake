# frozen_string_literal: true

namespace :mcp do
  namespace :tokens do
    desc "Issue an MCP gateway token. Args: NAME, SCOPES (csv, default: read)"
    task issue: :environment do
      name = ENV["NAME"].to_s.strip
      abort("usage: NAME=label SCOPES=read,write bin/rails mcp:tokens:issue") if name.empty?

      scopes = ENV.fetch("SCOPES", "read").split(",").map(&:strip).reject(&:empty?)
      result = McpAccessToken.issue!(name: name, scopes: scopes)

      puts "Issued token #{result.record.id} (#{name}) — scopes: #{scopes.join(",")}"
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
