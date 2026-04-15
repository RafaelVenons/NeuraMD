# CLAUDE.md

## Objetivo

Este arquivo é o guia único de uso do NeuraMD como plataforma de especificações vivas.
O banco de dados é a fonte da verdade. Markdowns servem apenas como bootstrap descartável.
O `CLAUDE.md` é o único arquivo markdown que permanece no repositório.

## Regra principal

- O acervo vivo está no banco, não em arquivos `.md`.
- Novas decisões, specs e documentação devem nascer como notas, não como markdown.
- Quando um `.md` é importado, ele pode ser removido do repositório após a importação.
- O pertencimento ao acervo é definido por **tags**, não pelo texto do título.
- Títulos naturais, sem prefixos artificiais.

## MCP Server

O NeuraMD expõe um servidor MCP (Model Context Protocol) via stdio.
Qualquer projeto com `.mcp.json` apontando para `bin/mcp-server` tem acesso direto às notas.

### Configuração

Arquivo `.mcp.json` na raiz do projeto consumidor:

```json
{
  "mcpServers": {
    "neuramd": {
      "command": "bin/mcp-server",
      "cwd": "/home/venom/projects/NeuraMD"
    }
  }
}
```

### Tools disponíveis

#### Leitura

| Tool | Descrição |
|------|-----------|
| `search_notes` | Busca por texto em títulos e conteúdo. `regex: true` habilita POSIX regex (case-insensitive, timeout 150ms). `property_filters` aceita JSON. |
| `read_note` | Lê nota completa por slug (com outgoing links e backlinks) |
| `list_tags` | Lista todas as tags com contagem de notas |
| `notes_by_tag` | Filtra notas por tag |
| `note_graph` | Vizinhos no grafo de uma nota |
| `recent_changes` | Lista notas ordenadas por head revision desc. Filtros: `since` (ISO8601), `tag`, `limit` (≤100) |

#### Escrita

| Tool | Descrição |
|------|-----------|
| `create_note` | Cria nota com título, conteúdo markdown e tags |
| `update_note` | Atualiza conteúdo, título, tags, aliases, propriedades e links |
| `patch_note` | Edita seção por heading: `append`, `prepend` ou `replace_section`. Cria checkpoint. Seção vai até o próximo heading de mesmo nível ou mais raso. |
| `manage_property` | Get/set/delete de uma única propriedade tipada. Validações do `Properties::SetService`; set/delete criam checkpoint. Valor aceita JSON ou string bruta. |
| `import_markdown` | Importa `.md` inteiro — cada heading vira nota |
| `merge_notes` | Merge source→target: appenda conteúdo, retargeta links, cria redirect, soft-deleta source |
| `find_anemic_notes` | Detecta notas com poucas linhas de conteúdo real, sugere targets de merge |

### Uso do MCP

- Projetos externos devem acessar o acervo via MCP, não referenciando a pasta do NeuraMD.
- `read_note` segue slug redirects e retorna outgoing links + backlinks.
- `update_note` aceita `append_links` para adicionar wikilinks sem reescrever o conteúdo.
- `import_markdown` processa `.md` por headings, cria links `c:` automáticos, sem metadados redundantes.

## Política de versionamento

Toda alteração de conteúdo de uma nota cria uma **revision checkpoint**.
Isso garante que qualquer estado anterior pode ser consultado e restaurado.

- `update_note` e `append_links` usam `CheckpointService` — cada chamada cria uma revision.
- `create_note` cria a nota já com um checkpoint inicial.
- `import_markdown` cria checkpoint para cada nota importada.
- A revision anterior permanece acessível via histórico (`/notes/:slug/revisions`).

Regra: **nunca alterar conteúdo de nota sem criar checkpoint**. Não usar `update_columns` para mudanças de conteúdo.

## Política de rastreabilidade

Ao concluir um EPIC, atualizar sua nota no acervo com uma seção **Arquivos-chave** listando:

- Migrations, models, services, controllers, rotas, views, JS controllers, CSS
- Specs correspondentes com breve descrição da cobertura

Isso evita varredura do código quando alguém precisa entender ou modificar a feature.
O objetivo não é listar cada arquivo tocado — apenas os pontos de entrada relevantes.

## Política de refatoração contínua

Ao atualizar uma nota via `update_note`, aproveitar para reorganizar quando conveniente:

- Quebrar notas longas em partes menores (alvo: 10-80 linhas).
- Remover metadados redundantes que pertençam a tags ou links, não ao corpo.
- Limpar cabeçalhos duplicados (ex: se o título já está no heading da nota).
- Atualizar links `c:` e `b:` para refletir a estrutura atual.
- Adicionar tags temáticas ausentes.
- Corrigir wikilinks órfãos ou desatualizados.

Isso não é obrigatório a cada update — é uma política de "reorganizar a casa" quando a oportunidade surge. O checkpoint garante que o estado anterior está preservado.

## Wikilinks e roles

Formato: `[[Display|role:uuid]]`

**IMPORTANTE: o identificador após o role é sempre o UUID da nota, nunca o slug.**
O UUID é imutável — renames não quebram links. Slugs mudam e causam links órfãos.

```
CORRETO:  [[Editor de Tabela|c:a3f1b2c4-5678-9abc-def0-123456789abc]]
ERRADO:   [[Editor de Tabela|c:editor-de-tabela]]
```

| Role | Semântica | Quando usar |
|------|-----------|-------------|
| (sem role) | Referência genérica | Link simples entre notas |
| `f:` | Father (pai) | Nota-filho apontando para seu pai (a nota-filho contém o link) |
| `c:` | Child (filho) | Nota-pai listando seus filhos (a nota-pai contém o link) |
| `b:` | Brother (lateral) | Catálogo de erros, testes correlatos, dependências |

### Regra de uso: `c:` OU `f:`, nunca ambos

Uma relação pai-filho usa **um único link**, não dois. Escolher conforme quem "possui" a lista:

- **Lista sequencial no pai** → usar `c:` na nota-pai. O filho **não** adiciona `f:`.
- **Filho referencia pai avulso** → usar `f:` na nota-filho. O pai **não** adiciona `c:`.

```
CORRETO — pai lista filhos com c:
  Nota "Fase 7":
    [[7.1 — Editor|c:uuid1]]
    [[7.2 — Table Editor|c:uuid2]]
  Nota "7.1 — Editor": (sem f: para Fase 7, já está ligado pelo c:)

CORRETO — filho aponta para pai com f:
  Nota "Bug #42":
    [[Fase 7|f:uuid-fase7]]
  Nota "Fase 7": (sem c: para Bug #42, já está ligado pelo f:)

ERRADO — duplicação
  Nota "Fase 7":
    [[7.1 — Editor|c:uuid1]]      ← c: no pai
  Nota "7.1 — Editor":
    [[Fase 7|f:uuid-fase7]]        ← f: no filho (DUPLICADO!)
```

- Links `b:` conectam notas por semelhança sem hierarquia (não duplicam com `c:`/`f:`).
- O SyncService processa wikilinks do corpo e cria NoteLinks automaticamente.
- **Toda nota deve ter pelo menos um wikilink** — nenhuma nota nasce órfã. Ao criar uma nota com `create_note`, incluir no conteúdo pelo menos um `[[pai|f:uuid]]` ou usar `append_links` logo em seguida. Notas sem links ficam invisíveis na navegação do grafo.

## Tags

Tags definem o pertencimento ao acervo e permitem recortes transversais.

### Acervos existentes

| Tag base | Descrição |
|----------|-----------|
| `plan` | Acervo histórico do plano (legado) |
| `new-specs` | Próxima iniciativa do NeuraMD |
| `queue` | Especificação de fila de serviços |
| `shop` | Plataforma shopAI |

### Tags estruturais (por acervo)

- `{acervo}-import` — lote de importação técnica (para reimport)
- `{acervo}-h1` a `{acervo}-h4` — nível hierárquico
- `{acervo}-raiz` — nota raiz do acervo
- `{acervo}-estrutura` — nota com filhos

### Regras de tags

- Uma nota pode ter múltiplas tags de acervos diferentes.
- Tags temáticas (ex: `plan-typewriter`, `shop-payments`) permitem recortes transversais.
- Tags inexistentes são criadas automaticamente pelo MCP.

## Importação de markdown

### Via MCP (preferencial)

```
import_markdown(
  markdown: "<conteúdo>",
  base_tag: "shop",
  import_tag: "shop-import",
  extra_tags: "iniciativa,estrutura-sistemica"
)
```

- Cada heading vira uma nota com corpo limpo.
- Links `c:` entre headings aninhados são criados automaticamente.
- Reimportação com mesmo `import_tag` limpa o lote anterior.
- Após importação, o `.md` pode ser removido — o acervo é a fonte viva.

### Via script legado (bootstrap)

- `bin/import-notes plan|new-specs|queue|all` — reimportação dos acervos bootstrap.
- Os scripts legados injetam metadados no corpo (Origem, Profundidade, Trilha, etc.).
- Para novas importações, preferir `import_markdown` via MCP (corpo limpo).

## Navegação

- Acessar acervo pela tag raiz (ex: `plan`, `new-specs`, `shop`).
- Navegar top-down pelas listas `c:` na nota raiz.
- Usar `f:` para navegação bottom-up.
- Usar `b:` para relações laterais e catálogos.
- Usar backlinks para índices não-sequenciais.
- Usar tags temáticas para recortes transversais.

## Testes

- RSpec local: `bundle exec rspec <arquivo>` para feedback rápido. Evitar rodar a suite inteira se puder (custo de CPU).
- **Playwright** via `bin/e2e-local` (com `bin/start` rodando).
- TDD estrito: teste falhando primeiro, depois implementação.

## Push

**Nunca fazer push sem validar a CI localmente.** Antes de `git push`, executar no mínimo:

```bash
bin/brakeman --no-pager        # security scan (0 warnings)
bin/rubocop                    # lint (0 offenses)
```

Se houver testes afetados pelas mudanças, rodá-los também antes do push.
Push com CI quebrando é **proibido**.

## Critério de qualidade

- Notas curtas (10-80 linhas) para leitura operacional.
- Corpo limpo — sem metadados que pertençam a tags/links.
- Árvore clara para navegação top-down.
- Catálogos `b:` sem duplicidade.
- Tags suficientes para recortes transversais.
- Cada update cria checkpoint para histórico restaurável.

## Persistência proativa no acervo

**Não esperar pressão de contexto para atualizar o NeuraMD.** Persistir em marcos naturais:

- Após concluir uma feature ou fix significativo
- Ao descobrir um bug ou tomar uma decisão técnica não óbvia
- Antes de mudar de assunto/tarefa dentro da mesma sessão
- Ao atingir 80% de contexto (hook automático vai lembrar)

Usar `update_note` ou `create_note` via MCP. O acervo é a memória que sobrevive entre sessões — o que não for persistido será perdido na compactação.

## Workflow de planejamento

**Antes de entrar em modo de planejamento (Plan mode), sempre consultar o acervo via MCP primeiro.**

O acervo contém specs, decisões arquiteturais, status de EPICs e contexto que não está no código.
Planejar sem ler o acervo resulta em planos desalinhados com decisões já tomadas.

Sequência obrigatória:
1. **Consultar MCP**: `search_notes`, `read_note`, `notes_by_tag` — buscar specs, EPICs e decisões relevantes à tarefa
2. **Examinar código**: ler arquivos-chave identificados nas notas ou no codebase
3. **Entrar em Plan mode**: com contexto completo do acervo + código

## Workflow de commit com auto-update

Quando o usuário pedir commit:
1. Fazer o commit normalmente (staged files, mensagem descritiva)
2. **Atualizar o acervo**: usar `update_note` para marcar EPICs/fases como COMPLETE com data, entregas e métricas
3. Se fase/iniciativa foi concluída, atualizar a nota-pai com status consolidado
4. Verificar notas anêmicas criadas pelo trabalho e sugerir consolidação

## Qualidade de notas — evitar notas anêmicas

Notas com menos de 10 linhas de conteúdo real são "anêmicas" e devem ser consolidadas:
- Usar `find_anemic_notes` para detectar
- Usar `merge_notes` para consolidar com nota pai ou irmã
- O merge redireciona links automaticamente (slug redirect + link migration)
- Ao importar specs, preferir notas densas (>15 linhas) a muitas notas finas

## Workflow Codex — Claude orquestra, Codex executa

O plugin Codex está integrado para que **Claude planeje e orquestre** enquanto **Codex executa código**. O `codex-gate` controla o orçamento de tokens.

### Quando Claude faz sozinho vs delega ao Codex

| Claude faz sozinho | Claude planeja + Codex executa |
|--------------------|-------------------------------|
| Mudanças < 3 arquivos | Features novas multi-arquivo |
| Fixes pontuais e bugs simples | Refactors estruturais |
| Configs, docs, specs, notas | Migrations + models + specs em lote |
| Edições de UI/CSS isoladas | Implementação de EPICs completos |
| Investigação e diagnóstico | Geração de test suites |

### Fluxo completo de delegação

1. **Claude analisa**: lê specs/notas via MCP, examina codebase, identifica padrões
2. **Claude planeja**: monta prompt detalhado seguindo o template abaixo
3. **Claude delega**: `/codex:rescue --write "prompt"`
4. **Claude valida**: revisa diff, roda testes, verifica padrões
5. **Se precisa ajuste**: `/codex:rescue --resume "corrigir X"`
6. **Review gate**: `codex-gate` → `/codex:review --wait` (se budget permitir)
7. **Commit**: com findings resolvidos

### Template de prompt para delegação

Ao delegar ao Codex, Claude deve montar o prompt com esta estrutura:

```
Projeto: [nome e stack — ex: NeuraMD, Rails 8, Hotwire, PostgreSQL]
Contexto: [o que existe hoje, arquivos relevantes, padrões em uso]
Tarefa: [o que implementar, com critérios de aceite claros]
Arquivos a criar/modificar: [lista explícita]
Padrões a seguir: [convenções, naming, estrutura de testes]
Testes esperados: [quais specs criar, cobertura mínima]
Não fazer: [restrições — ex: não alterar migrations existentes, não adicionar gems]
```

Quanto mais preciso o prompt, melhor o resultado. Incluir trechos de código existente como referência quando relevante.

### Exemplos de delegação

**Feature nova:**
```
/codex:rescue --write "
Projeto: NeuraMD, Rails 8, Hotwire, PostgreSQL
Contexto: Notes::MergeService já existe em app/services/notes/merge_service.rb.
  Ele recebe source e target, appenda conteúdo, cria redirect e retargeta links.
Tarefa: Criar endpoint REST para merge de notas via API JSON.
  POST /api/notes/:slug/merge com body { target_slug: 'xxx' }.
  Retornar 200 com nota merged ou 422 com errors.
Arquivos: app/controllers/api/notes_controller.rb (action merge),
  config/routes.rb (adicionar rota), spec/requests/api/notes_merge_spec.rb
Padrões: controllers API herdam de Api::BaseController, specs usam FactoryBot.
Testes: spec cobrindo merge sucesso, source não encontrado, target não encontrado,
  self-merge rejeitado.
Não fazer: não alterar MergeService, não adicionar autenticação (já existe no BaseController).
"
```

**Refactor multi-arquivo:**
```
/codex:rescue --write "
Projeto: NeuraMD, Rails 8
Contexto: StateStore em codextokens/state.py tem 586 linhas com session mgmt,
  auth tokens, webhooks e review gate misturados.
Tarefa: Extrair review gate para módulo separado review_gate_store.py.
  Mover evaluate_review_gate, _planned_token_count, _normalize_gate_*.
  StateStore deve delegar para ReviewGateStore.
Arquivos: codextokens/review_gate_store.py (novo), codextokens/state.py (refactor)
Padrões: mesma convenção de locks e _save() do StateStore.
Testes: mover testes relevantes de test_state.py para test_review_gate_store.py.
Não fazer: não mudar a API HTTP, não alterar server.py.
"
```

**Lote de testes:**
```
/codex:rescue --write "
Projeto: NeuraMD, Rails 8, RSpec
Contexto: MCP tools em lib/mcp/tools/ seguem padrão MCP::Tool com .call().
  Exemplo: search_notes_tool.rb retorna {notes: [...]} ou error_response('msg').
Tarefa: criar specs para merge_notes_tool e find_anemic_notes_tool.
Arquivos: spec/lib/mcp/tools/merge_notes_tool_spec.rb,
  spec/lib/mcp/tools/find_anemic_notes_tool_spec.rb
Padrões: usar FactoryBot, testar happy path + edge cases + error responses.
  Verificar com response.error? (não response.error).
Não fazer: não alterar os tools, apenas criar specs.
"
```

### Continuação de thread

Se o Codex entregou resultado parcial ou precisa de ajuste:

```
/codex:rescue --resume "Os testes de merge passaram mas falta o caso de self-merge.
Adicionar spec que verifica ArgumentError quando source == target."
```

### Review gate

Antes de qualquer review, verificar orçamento via `codex-gate` (lê o contexto da statusline):

```bash
codex-gate   # exit 0 = permitido, exit 2 = bloqueado (contexto >= 75%)
```

### Quando usar cada tipo de review

| `/codex:review --wait` | `/codex:adversarial-review --wait` |
|------------------------|-----------------------------------|
| Qualquer implementação significativa | Mudanças estruturais (migrations, models) |
| Pós-delegação ao Codex | Mudanças de segurança (auth, sanitização) |
| Antes de merge/PR | Refactors que mudam contratos |

**Regra crítica**: após review, apresentar findings ao usuário — **nunca corrigir automaticamente**.

## Planejamento e acervo

Ao planejar qualquer mudança (inclusive em Plan Mode), **sempre consultar o acervo MCP primeiro**:
- `mcp__neuramd__search_notes` para encontrar specs, decisões e contexto relacionados
- `mcp__neuramd__notes_by_tag` para explorar domínios (e.g., `import`, `grafo`, `ai`, `spec`)
- O acervo contém decisões arquiteturais, contratos e histórico que devem informar o plano

Ao finalizar trabalho, **atualizar o acervo imediatamente** (não esperar o fim da conversa):
- Sync após cada commit ou milestone significativo
- Se o contexto comprimir antes do sync, as atualizações se perdem

## Design de UI/UX (para projetos consumindo NeuraMD)

Princípios para interfaces de projetos que usam o acervo via MCP:
- Design system: cores, tipografia, espaçamento como tokens
- Mobile-first, progressive enhancement
- Acessibilidade: semântica HTML, contraste WCAG AA, navegação por teclado
- Feedback visual imediato + estados (loading, empty, error, success)
- Animações sutis (< 300ms) para transições
