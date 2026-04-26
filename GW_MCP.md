Contexto: o NeuraMD expõe um MCP server stdio via bin/mcp-server
(Ruby, MCP::Server::Transports::StdioTransport, tools em lib/mcp/tools/).
Preciso expor esse MCP server remotamente via rede para clientes MCP
externos (não-stdio).

Tarefa: implementar um Gateway MCP HTTP no próprio Rails, montado em
/mcp, usando o transport Streamable HTTP da spec MCP
(https://modelcontextprotocol.io/specification/2025-06-18/basic/transports).

Requisitos não-funcionais (críticos):
1. Autenticação obrigatória — bearer token via header
   Authorization, validado contra um modelo McpAccessToken (ou
   ApiToken) com escopos. Sem token => 401. Tokens revogáveis.
2. Reusar Mcp::Tools.all sem duplicar registro de ferramentas.
3. Whitelist explícita de tools expostas remotamente em config
   (config/mcp_remote.yml). Tools de escrita (create_note, update_note,
   patch_note, merge_notes, bulk_remove_tag, spawn_child_tentacle)
   exigem escopo write no token.
4. Rate limit por token (Rack::Attack) — default 60 req/min, configurável.
5. Logs estruturados de cada chamada: token_id, tool, latência, status,
   erro (sem vazar conteúdo de notas no log).
6. Tratamento de falhas: timeout por chamada (30s default), resposta
   JSON-RPC error 2.0 padrão MCP, sem stacktrace vazado.
7. Bind por padrão em 127.0.0.1; exposição em LAN somente via reverse
   proxy (documentar no README).
8. Testes RSpec cobrindo: auth válida, auth inválida, escopo
   insuficiente, tool fora da whitelist, rate limit, timeout,
   payload malformado, JSON-RPC error shape correto.

Entregáveis:
- app/controllers/mcp_controller.rb (ou engine isolado em lib/)
- config/initializers/mcp_remote.rb
- config/mcp_remote.yml.example
- db/migrate para McpAccessToken (token hash, scopes, last_used_at,
  revoked_at)
- spec/requests/mcp_spec.rb
- README seção "Remote MCP Gateway" com exemplo de curl JSON-RPC
  initialize/tools/list/tools/call e exemplo de configuração em cliente
  MCP externo.

Antes de codar: liste suposições sobre a versão da gem `mcp` em uso
(Gemfile.lock), confirme se ela já tem transport HTTP nativo ou se
precisaremos implementá-lo, e proponha alternativas se a gem não
suportar Streamable HTTP. Não assuma — verifique.
