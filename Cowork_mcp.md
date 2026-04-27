Você vai trabalhar no NeuraMD (Rails 8). Repo: https://github.com/RafaelVenons/NeuraMD.
Checkout vivo no host do gateway: rafael@192.168.100.112:~/apps/NeuraMD (SSH key
já configurada). Runtime: puma na porta 3000, RAILS_ENV=production, Ruby 3.3.10
via mise (PATH=$HOME/.local/share/mise/shims:$PATH), BUNDLE_DEPLOYMENT=true,
BUNDLE_WITHOUT="development:test". Rakes/runners exigem RAILS_ENV=production.

## Objetivo

Permitir que um cliente MCP remoto (Claude Code rodando fora da máquina, autenticado
pelo gateway HTTP em /mcp) envie comandos ao "gerente" (slug "gerente" — orquestrador
principal do NeuraMD) e leia as respostas dele, SEM expor a fábrica de tentáculos
toda como zona aberta.

## Estado atual (já mapeado, não precisa redescobrir)

- Gateway: app/controllers/mcp_controller.rb + config/initializers/mcp_remote.rb
  carrega whitelist de config/mcp_remote.yml (cai em .yml.example se ausente).
- Tools de agente JÁ existem em lib/mcp/tools/:
    send_agent_message_tool.rb        → AgentMessages::Sender
    read_agent_inbox_tool.rb          → AgentMessages::Inbox
    spawn_child_tentacle_tool.rb      → Tentacles::ChildSpawner
    activate_tentacle_session_tool.rb → POST S2S /api/s2s/tentacles/:slug/activate
    route_human_to_tool.rb            → exige server_context[:tentacle_id]
  Estão em Mcp::Tools.all (lib/mcp/tools.rb) e funcionam dentro de tentáculos stdio.
- Em config/mcp_remote.yml.example, as 5 tools de agente estão comentadas com aviso
  explícito sobre o risco de write-scope leak.
- McpAccessToken (app/models/mcp_access_token.rb, schema em db/schema.rb) tem só
  name/scopes[]/token_hash/revoked_at/last_used_at. NÃO tem identidade de agente.
- Há um único token "claude-code" registrado, com scopes read,write,tentacle
  (id 7fcb47c1-d7a3-4057-83ed-e0d043f36d1e).
- Slug "gerente" existe e tem o título "Gerente". Tag esperada de agentes: "agente-*"
  (validada por SpawnChildTentacleTool e ActivateTentacleSessionTool).
- Tarefas de token: lib/tasks/mcp_tokens.rake (issue/list/revoke).

## Riscos a NÃO ignorar

A. Falsificação de remetente: send_agent_message aceita from_slug arbitrário. Sem
   amarração, qualquer cliente com escopo tentacle injeta mensagens em nome de
   qualquer nota.
B. Spawn descontrolado: spawn_child_tentacle exposto cru permite criar tentáculos
   externamente; combinado com tentacle_workspace pode gravar em workspaces fora
   da raiz pretendida.
C. activate_tentacle_session já chama a API S2S interna; expor exige garantir que
   AGENT_S2S_TOKEN está setado no systemd unit do neuramd-web.
D. route_human_to depende de server_context[:tentacle_id] — não é gateway-friendly.

## Antes de implementar — leve estas decisões ao usuário

1. Modelo de identidade: prefere
   (a) adicionar McpAccessToken.agent_note_id (uuid, FK opcional para Note) e
       resolver from_slug a partir do token, OU
   (b) criar tools dedicadas talk_to_manager / read_manager_replies que escondem
       from_slug e têm to_slug fixo no "gerente", OU
   (c) ambos — token traz identidade E há um par de tools de alto nível?
2. Cada token deve ganhar uma "nota-espelho" (ex.: claude-code-remoto) criada
   automaticamente no issue, ou o operador associa manualmente?
3. Acordar o gerente: quando a mensagem chegar, chamar ActivateTentacleSession
   automaticamente (síncrono dentro da tool), ou deixar isso a cargo do cliente?
4. Polling vs streaming: read_my_inbox via long-poll bloqueante (espera por
   delivered_at) ou só snapshot? E qual TTL razoável?
5. Spawn remoto: liberar spawn_child_tentacle pelo gateway ou manter intra-tentáculo?
   Se liberar, qual restrição extra (ex.: parent_slug precisa pertencer ao agent_note
   do token)?

NÃO comece a codar antes de alinhar essas 5 decisões com o usuário. Liste as
opções, mostre tradeoffs, espere resposta.

## Quando estiver alinhado, plano provável

1. Migration: add column agent_note_id (uuid, nullable, FK -> notes) a
   mcp_access_tokens. Atualizar McpAccessToken (validação opcional, helper
   #agent_note).
2. Atualizar lib/tasks/mcp_tokens.rake (`issue`) para aceitar AGENT_SLUG= e
   gravar agent_note_id; documentar no README/CLAUDE.md.
3. Criar Mcp::Tools::TalkToManagerTool (ou nome decidido) que:
   - resolve from a partir de current_mcp_token (passado via server_context)
   - to fixo em "gerente" (ou whitelist por mcp_remote.yml)
   - chama AgentMessages::Sender + (opcional) ActivateTentacleSession
   - retorna message_id pro caller
4. Criar Mcp::Tools::ReadManagerRepliesTool: usa AgentMessages::Inbox no
   agent_note do token, com mark_delivered opcional (default false).
5. Propagar current_mcp_token no server_context. Hoje McpController não passa
   nada — vai precisar customizar o transport ou usar um wrapper. Verificar
   como o mcp gem expõe isso (RemoteMcpGateway.transport recebe MCP::Server,
   pode ser preciso passar context_provider).
6. Editar config/mcp_remote.yml.example: adicionar as duas tools novas com
   scope: tentacle, manter as 5 internas comentadas, adicionar comentário
   explicando que talk_to_manager substitui send_agent_message para uso remoto.
7. Criar config/mcp_remote.yml de produção no host (cópia do example com as
   novas linhas ativas). NÃO commitar — é arquivo de operador.
8. Specs: spec/requests/mcp_controller_spec.rb (ou criar) cobrindo:
   - tool não exposta sem whitelist
   - tool exposta sem agent_note_id no token → erro claro
   - happy path (mensagem entra no inbox do gerente)
   - read_manager_replies só lê inbox do agent_note do token (não vaza outros)
9. Atualizar CLAUDE.md / README com como o remoto fala com o gerente.

## Critérios de aceitação

- bin/rails mcp:tokens:issue NAME=foo SCOPES=read,write,tentacle AGENT_SLUG=foo-bot
  cria token + amarra ao slug "foo-bot".
- POST /mcp com tools/call name=talk_to_manager arguments={content:"oi"} entra no
  inbox do gerente com from_slug = nota do token. Tentativa de passar from_slug
  ou to_slug arbitrário via arguments é ignorada/rejeitada.
- POST /mcp com tools/call name=read_manager_replies retorna só mensagens do
  inbox do agent_note do token. Outro token não vê.
- send_agent_message cru continua bloqueado pelo whitelist (não expor).
- Specs verdes; rubocop limpo se o projeto usar.
- Após reload do puma, o cliente Claude Code remoto vê as duas novas tools no
  list_tools e consegue conversar com o gerente.

## Convenções do repo

- Veja CLAUDE.md no root para estilo e workflow.
- Migrations: bin/rails g migration sob RAILS_ENV=production no host, mas a
  prática usual é gerar local, commitar, e o autodeploy faz git reset --hard +
  db:migrate. Confirme com o usuário antes de aplicar manualmente.
- BUNDLE_DEPLOYMENT impede bundle install de gravar Gemfile.lock — use bundle
  config localmente se precisar adicionar gem.

## Restrição importante

NÃO faça `git reset --hard` no host (autodeploy faz isso) e NÃO mexa em
~/NeuraMD ou ~/projects/NeuraMD (são clones obsoletos). O checkout vivo é
~/apps/NeuraMD.
