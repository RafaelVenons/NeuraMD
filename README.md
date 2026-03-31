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

## License

Private — all rights reserved.
