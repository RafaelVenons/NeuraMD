# NeuraMD

A self-hosted, structured knowledge platform built with Rails 8 and PostgreSQL.
NeuraMD turns plain Markdown notes into a richly connected knowledge graph with full-text search, AI-powered capabilities, and text-to-speech — all under your control.

## Features

- **Markdown editor** — CodeMirror 6 with live preview, typewriter mode, and structural reveal
- **Wiki-links** — `[[bidirectional links]]` with automatic backlink tracking and link promises
- **Knowledge graph** — interactive Sigma.js visualization with recursive CTEs and tag filters
- **Full-text search** — PostgreSQL `tsvector` + `pg_trgm` trigram fuzzy matching, regex support
- **Tags** — hierarchical tagging with global and per-note scoping
- **Versioning** — immutable revision history for every note
- **AI capabilities** — pluggable provider architecture (Ollama, OpenAI-compatible), grammar review, rewrite, suggestions, and translation (pt-BR / en)
- **Text-to-Speech** — 4 TTS providers, SHA-256 audio cache, karaoke highlighting with MFA alignment
- **MCP server** — Model Context Protocol (stdio) exposing notes to any AI agent or IDE
- **Slug redirects** — rename notes without breaking links, bookmarks, or external references
- **E2E testing** — Playwright browser tests for critical user flows

## Stack

| Layer | Technology |
|-------|-----------|
| Framework | Rails 8.1, Hotwire (Turbo + Stimulus) |
| Database | PostgreSQL with `pg_search`, encrypted attributes |
| Frontend | Tailwind CSS, Importmap, CodeMirror 6 |
| Background | Solid Queue, Solid Cache |
| Auth | Devise + Pundit |
| Graph | Sigma.js + recursive CTEs |
| AI | Ollama / OpenAI-compatible providers |
| TTS | Kokoro, with MFA alignment pipeline |
| Deploy | Kamal, self-hosted |
| Tests | RSpec, Playwright |

## Getting started

```bash
# Dependencies
bundle install
npm install

# Database
bin/rails db:setup

# Start development server
bin/dev
```

## Testing

```bash
# Unit and integration specs
bundle exec rspec

# E2E browser tests
npx playwright install chromium
npm run e2e
```

## Remote MCP Gateway

The MCP server is also reachable over HTTP at `POST /mcp` for clients that
can't (or shouldn't) speak stdio. Auth is bearer-token; the whitelist of
exposed tools and the scope each one requires is declarative.

### Setup

```bash
# 1. Copy the example config and adjust if needed (defaults expose
#    read+write note tools + the talk_to_agent / read_my_inbox pair;
#    raw agent-mesh tools are commented out).
cp config/mcp_remote.yml.example config/mcp_remote.yml

# 2. Issue a token. Print-once — store it in your password manager.
#    Add AGENT_SLUG=<slug> to bind the token to a note, which is
#    required for the conversation tools (see "Talking to other agents").
NAME=my-laptop SCOPES=read,write bin/rails mcp:tokens:issue
NAME=remote-claude SCOPES=read,write,tentacle AGENT_SLUG=claude-code-remoto bin/rails mcp:tokens:issue

# 3. (Recommended) Bind only on loopback and front with a TLS reverse
#    proxy (nginx/caddy). The Rails app itself listens on 0.0.0.0; the
#    proxy is what makes the gateway reachable on the LAN.
```

Token management:

```bash
bin/rails mcp:tokens:list
ID=<uuid> bin/rails mcp:tokens:revoke
```

### Talking to the gateway

```bash
TOKEN="<paste plaintext from issue step>"
BASE="http://127.0.0.1:3000/mcp"

# initialize handshake
curl -sS -X POST "$BASE" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"curl","version":"1"}}}'

# list exposed tools
curl -sS -X POST "$BASE" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" -H "Accept: application/json" \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/list"}'

# call a tool (read scope sufficient for search_notes)
curl -sS -X POST "$BASE" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" -H "Accept: application/json" \
  -d '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"search_notes","arguments":{"query":"deploy"}}}'
```

### Talking to other agents

A bounded conversation surface for remote agents (e.g. a Claude Code
session running on a laptop). The token must have been issued with
`AGENT_SLUG=<note-slug>`; the tools refuse to run otherwise. Sender
identity is locked to the token's bound note (`from_slug` arguments
are silently ignored). Recipient must carry an `agente-*` tag — a
stolen token can't message arbitrary humans / notes.

```bash
# Send a message to any agent (auto-wakes the recipient's tentacle).
# Pass slug="gerente" to address the orchestrator, or any other
# agent slug for direct contact.
curl -sS -X POST "$BASE" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" -H "Accept: application/json" \
  -d '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"talk_to_agent","arguments":{"slug":"gerente","content":"Subi os fixes de CI, posso rebatch dos PRs?"}}}'

# Read your own inbox (newest first, only_pending by default). Pass
# mark_delivered:true once you've actually consumed the messages.
curl -sS -X POST "$BASE" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" -H "Accept: application/json" \
  -d '{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"read_my_inbox","arguments":{"only_pending":true}}}'
```

The raw mesh (`send_agent_message`, `spawn_child_tentacle`,
`activate_tentacle_session`, `read_agent_inbox`, `route_human_to`)
stays commented out in `config/mcp_remote.yml.example`. They accept
arbitrary slugs and would let a leaked token impersonate any agent or
spawn worktrees — keep them off unless you have a specific reason.

### MCP client config (e.g. Claude Code, Continue, etc.)

For a client that supports Streamable HTTP transport with a bearer header:

```json
{
  "mcpServers": {
    "neuramd-remote": {
      "transport": "streamable_http",
      "url": "https://your-host.example/mcp",
      "headers": { "Authorization": "Bearer <token>" }
    }
  }
}
```

### Tuning

- `NEURAMD_MCP_RATE_LIMIT_PER_MIN` — per-token throttle (default 60/min)
- `NEURAMD_MCP_CALL_TIMEOUT_SECONDS` — per-call timeout (default 30s)
- `config/mcp_remote.yml` — tool whitelist + scope map (see `.example`)

Errors come back JSON-RPC shaped (`-32001` unauthorized / scope, `-32601`
tool not exposed, `-32603` timeout/internal, `-32000` rate limit).

## License

Private — all rights reserved.
