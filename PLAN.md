# PLAN — NeuraMD (Rails 8, Hotwire, PostgreSQL, Self-Hosted)

> **Inspiração base:** FrankMD (`../FrankMD`) — editor Markdown self-hosted em Rails 8, sem banco de dados, filesystem-based.
> **NeuraMD** evolui o conceito adicionando PostgreSQL, versionamento de conteúdo, grafo semântico de notas, tags, mídia e IA plugável.

---

## 1. Objetivo

Aplicação self-hosted de notas com:

- Editor Markdown + Preview HTML (base do FrankMD, portado e adaptado)
- **Banco de dados** PostgreSQL (diferencial vs FrankMD)
- Relações semânticas entre notas com **teoria de grafos**
- Versionamento de conteúdo com restauração de revisões
- Mídia (imagens/áudios/vídeos) e embeds
- Grafo navegável na Web
- Tags N:N para notas e links (com cores/ícones)
- IA plugável: sugestão e revisão gramatical com diff (base FrankMD)
- TTS sob demanda com cache: ElevenLabs e Fish Audio — geração manual, multi-idioma, suporte a Mandarim/Japonês/Coreano
- **Armazenamento local** com interface agnóstica (trocar backend sem reescrever código)
- Docker para deploy self-hosted
- API REST preparada para cliente iPad futuro

---

## 2. Stack

### Backend
- Ruby on Rails 8
- PostgreSQL (com `pg_trgm`, `tsvector`, CTEs recursivas para grafo)
- Active Storage com **adapter local por padrão** — interface agnóstica para troca futura
- Active Record Encryption (campos sensíveis via ENV/credentials)
- Devise (autenticação) + Pundit (autorização)

### Frontend Web
- Tailwind CSS
- Hotwire (Turbo + Stimulus) — mesma abordagem do FrankMD
- CodeMirror 6 — mesmo editor do FrankMD
- Preview HTML client-side via `marked.js` + extensões locais de wikilink
- Suporte a Unicode completo: Mandarim (CJK), Japonês (Hiragana/Katakana/Kanji), Coreano (Hangul)

### Infra
- Docker + docker-compose
- Reverse proxy recomendado: Caddy ou Nginx

---

## 3. O que Reaproveitar do FrankMD

O FrankMD implementa bem (usar como referência de implementação, não copiar código diretamente).
O objetivo é portar o máximo de funcionalidades de usabilidade, adaptando para banco de dados e
armazenamento local em vez de filesystem + S3.

| Funcionalidade | Status no FrankMD | Ação |
|---|---|---|
| CodeMirror 6 com syntax highlight | ✅ Implementado | Adaptar para salvar no banco |
| Preview HTML com sanitização | ✅ Implementado | Reaproveitar |
| Autosave com política (não a cada tecla) | ✅ Implementado | Reaproveitar — salva em `note_revisions` |
| Find/replace e jump-to-line (client-side) | ✅ Implementado | Reaproveitar |
| Offline detection + content loss protection | ✅ Implementado | Reaproveitar |
| Atalhos bold/italic/heading/list | ✅ Implementado | Reaproveitar |
| Scroll sync editor ↔ preview | ✅ Implementado | Reaproveitar |
| Typewriter mode | ✅ Implementado | Reaproveitar |
| Embed YouTube | ✅ Implementado | Reaproveitar |
| Grid de imagens + inserção no markdown | ✅ Implementado | Adaptar para Active Storage local |
| IA: Grammar checking + sugestão | ✅ Implementado | Reaproveitar + expandir providers |
| Themes dark/light | ✅ Implementado | Reaproveitar |
| Deploy Docker | ✅ Implementado | Adaptar com postgres/redis |
| Stats: palavras/linhas/posição | ✅ Implementado | Reaproveitar |
| Cheatsheet Markdown | ✅ Implementado | Reaproveitar |
| Code block dialog + autocomplete linguagem | ✅ Implementado | Reaproveitar |
| **Banco de dados** | ❌ Filesystem apenas | **Implementar do zero** |
| **Versionamento de conteúdo** | ❌ Não tem | **Implementar do zero** |
| **Grafo semântico de notas** | ❌ Não tem | **Implementar do zero** |
| **Tags N:N** | ❌ Não tem | **Implementar do zero** |
| **TTS (ElevenLabs/Fish Audio)** | ❌ Não tem | **Implementar do zero** |
| **Suporte CJK/Japonês/Coreano** | ❌ Não tem | **Implementar do zero** |
| **Armazenamento agnóstico** | ❌ S3 hardcoded | **Implementar do zero** |

---

### 3.1 Regras de Reaproveitamento

- **Reaproveitar arquitetura e UX, não copiar acoplamentos antigos.**
- FrankMD é referência primária para:
  - controllers Stimulus do editor
  - ergonomia de toolbar/dialog
  - fluxo de diff/apply de IA
  - estratégia de testes de sistema para features interativas do editor
- FrankMD **não** deve ser copiado literalmente quando a implementação original depende de:
  - filesystem como source of truth
  - configuração em `.fed`
  - serviços ou models inexistentes no NeuraMD
  - storage S3 hardcoded
- Sempre que houver divergência:
  - **UX do FrankMD** pode ser mantida
  - **persistência, autorização, auditoria e domínio** devem seguir o NeuraMD

### 3.2 Reaproveitamento Específico da Fase 5

Para IA de texto, o FrankMD serve como referência nas seguintes peças:

| Peça no FrankMD | O que aproveitar | O que adaptar no NeuraMD |
|---|---|---|
| `app/controllers/ai_controller.rb` | formato dos endpoints de status + processamento | trocar leitura de arquivo por `Note`/`NoteRevision`; usar Pundit; responder por `slug` |
| `app/services/ai_service.rb` | separação entre escolha de provider, prompt e chamada remota | dividir em `app/services/ai/*`; auditar em `ai_requests`; usar `ai_providers` + ENV |
| `app/javascript/controllers/ai_grammar_controller.js` | fluxo do modal, overlay de processamento, diff/apply | operar sobre CodeMirror e seleção atual; aplicar em documento inteiro ou trecho |
| `app/views/notes/dialogs/_ai_diff.html.erb` | estrutura visual do diff lado a lado | encaixar no layout atual do editor sem reintroduzir dependências do app FrankMD |
| `app/javascript/lib/diff_utils.js` | diff textual puro e testável | manter como utilitário local reaproveitável por outras features |

### 3.4 Ambiente Inicial de IA Local

Para a primeira rodada de testes da Fase 5, considerar o seguinte ambiente como baseline:

- servidor local de IA acessível pelo hostname `AIrch`
- entrada já resolvida via `/etc/hosts`
- serviço Ollama escutando em `AIrch:11434`
- modelo inicial: `qwen3.5:4b`

**Convenção atual do projeto para testes locais de IA:**

- `AI_PROVIDER=ollama`
- `AI_ENABLED_PROVIDERS=ollama`
- `OLLAMA_API_BASE=http://AIrch:11434`
- `OLLAMA_MODEL=qwen3.5:4b`

Isso deve ser tratado como o caminho padrão de validação inicial antes de habilitar providers externos.

**Regra operacional para integrações com `AIrch`:**

- requisições para `AIrch` devem ser tratadas como **assíncronas por padrão**
- tempo real não é prioridade
- a UI deve preferir:
  - enqueue de job
  - estado persistido no banco
  - polling leve, Turbo Stream ou refresh manual
- evitar requests síncronos longos bloqueando o editor

### 3.3 Bibliotecas e Ferramentas de Qualidade a Manter como Referência

Bibliotecas já adotadas no NeuraMD e que devem continuar sendo a base de qualidade:

- `RSpec`
- `FactoryBot`
- `Shoulda Matchers`
- `DatabaseCleaner`
- `Capybara`
- `Cuprite` / `Ferrum`

Na fase 5, a regra é:

- testes de request para contratos HTTP e auditoria
- testes de service para prompts, seleção de provider e tratamento de erro
- testes de system para fluxo real no editor com dialog, diff e aplicação
- **não** depender de API real de IA em teste automatizado
- stubs devem ocorrer no boundary do provider/service, nunca dentro do CodeMirror

---

## 4. Modelo de Dados

### 4.1 Notes e Revisões

```
notes
  id                UUID PK
  title             string NOT NULL
  slug              string UNIQUE
  note_kind         enum (markdown, mixed)
  detected_language string (ex: pt-BR, en-US, zh-CN, ja-JP, ko-KR — detectado automaticamente)
  head_revision_id  UUID FK → note_revisions (nullable no início)
  created_at        timestamp
  updated_at        timestamp
  deleted_at        timestamp (soft delete)

note_revisions
  id                UUID PK
  note_id           UUID FK → notes
  author_id         UUID FK → users (nullable se single-user)
  base_revision_id  UUID FK → note_revisions (nullable; futuro: merge)
  content_markdown  text ENCRYPTED
  content_plain     text (derivado; para indexação e preview rápido)
  change_summary    string (legado; fora do fluxo atual da UI)
  revision_kind     enum (draft, checkpoint) DEFAULT draft
  ai_generated      boolean DEFAULT false
  created_at        timestamp
```

**Regras:**
- `revision_kind = draft` — gerada automaticamente pelo servidor a cada ~60s; apenas a mais recente é mantida por nota (a anterior é deletada); NÃO aparece no histórico de versões
- `revision_kind = checkpoint` — criada pelo botão "Salvar" manual; mantida para sempre; aparece no histórico com timestamp e diff
- `notes.head_revision_id` aponta sempre para o checkpoint mais recente (não para drafts)
- Restaurar = criar novo checkpoint com conteúdo da revisão histórica + atualizar `head_revision_id`
- `content_plain` é derivado do markdown para busca (não editável diretamente)
- `detected_language` é atualizado no save via detecção automática (gem `cld3` ou similar) — usado pelo TTS como idioma padrão

---

### 4.2 Grafo Semântico — Links entre Notas

#### Formato Wiki-Link no Markdown

Links semânticos são escritos diretamente no texto da nota como wiki-links de duplo colchete:

```
[[Display Text|uuid]]          → referência simples (hier_role = NULL)
[[Display Text|f:uuid]]        → Father  — dst está ACIMA na hierarquia (target_is_parent)
[[Display Text|c:uuid]]        → Child   — dst está ABAIXO na hierarquia (target_is_child)
[[Display Text|b:uuid]]        → Brother — dst está no mesmo nível     (same_level)
```

**Separação de responsabilidades:**
- **Display Text** (antes do `|`) — texto livre escolhido pelo autor; pode ser alterado a qualquer momento sem quebrar o link; não precisa ser o título da nota destino
- **UUID** (depois do `|`) — referência imutável à nota destino; nunca muda mesmo se a nota for renomeada
- **Prefixo de role** (`f:`, `c:`, `b:`) — embutido antes do UUID; ausência = referência simples

**Fluxo de inserção:**
1. Usuário digita `[[`
2. Dropdown abre com sugestões filtradas pelo título da nota (busca em tempo real)
3. Usuário navega com `↓`/`↑`, seleciona com `Enter` ou `Tab`
4. Editor insere `[[Título da Nota|uuid]]` — o Display Text inicial é o título atual da nota
5. Após inserção, o usuário pode editar o Display Text livremente (o UUID permanece intacto)
6. Para definir `hier_role`, o usuário edita manualmente o prefixo: `|uuid` → `|f:uuid`

**Comportamento no editor (Stimulus + CodeMirror):**

| Situação | Comportamento |
|---|---|
| Digita `[[` | Abre dropdown de sugestões por título |
| Continua digitando `[[texto` | Filtra sugestões em tempo real via `GET /notes/search?q=` |
| `↓` / `↑` | Navega no dropdown |
| `Enter` ou `Tab` | Insere `[[Título\|uuid]]` no cursor |
| `Esc` | Fecha dropdown sem inserir |
| UUID não encontrado no DB | Fundo vermelho na marcação (`wikilink-broken`) no editor e no preview |
| Mesmo UUID repetido no texto | Aceito; `note_links` deduplicado por `(src_note_id, dst_note_id, hier_role)` |

**Preview:**
- `[[Display Text|uuid]]` → `<a href="/notes/slug" title="Título atual da nota">Display Text</a>`
- O `title` do `<a>` é buscado do DB pelo UUID — exibe o título real da nota em tooltip
- UUID inexistente → `<span class="wikilink-broken" title="Nota não encontrada">Display Text</span>`
- `TitleSyncService` **não é necessário** — Display Text é livre; sem propagação automática

**Backlinks no preview:**
- Seção no rodapé do preview listando todas as notas que linkam para esta
- Cada entrada: título da nota src com link para ela (`/notes/:slug`)
- Só aparece no preview, não no editor

```
note_links
  id                     UUID PK
  src_note_id            UUID FK → notes  (nota que DECLAROU o link)
  dst_note_id            UUID FK → notes  (nota referenciada)
  hier_role              enum nullable (target_is_parent, target_is_child, same_level)
  created_in_revision_id UUID FK → note_revisions (checkpoint que criou/atualizou o link)
  context                jsonb (posição/trecho/anchor — opcional)
  created_at             timestamp
```

**Semântica do `hier_role`:**

```
hier_role = target_is_parent  → dst está hierarquicamente ACIMA de src
hier_role = target_is_child   → dst está hierarquicamente ABAIXO de src
hier_role = same_level        → dst está no mesmo nível que src
hier_role = NULL              → referência simples sem semântica hierárquica
```

**Regras e direção do grafo:**

```
Nota B referencia Nota A:
  src = Nota B (quem DECLAROU o link)
  dst = Nota A (quem foi referenciada)

Backlinks de A   = SELECT * FROM note_links WHERE dst_note_id = A
Links de saída B = SELECT * FROM note_links WHERE src_note_id = B
```

**Diagrama visual da semântica:**
```
[src Father ] \→                   /→ [dst Father]
[src Brother] -→ [Nota em destaque]-→ [dst Brother]
[src Child  ] /→                   \→ [dst Child]
```

**Queries de grafo com CTE recursiva (PostgreSQL):**

```sql
-- Todos os descendentes de uma nota (hierarquia para baixo)
WITH RECURSIVE descendants AS (
  SELECT dst_note_id, 1 AS depth
  FROM note_links
  WHERE src_note_id = :note_id
    AND hier_role = 'target_is_child'
  UNION ALL
  SELECT nl.dst_note_id, d.depth + 1
  FROM note_links nl
  JOIN descendants d ON nl.src_note_id = d.dst_note_id
  WHERE nl.hier_role = 'target_is_child'
    AND d.depth < 10
)
SELECT * FROM descendants;

-- Caminho entre duas notas (BFS via CTE recursiva)
-- Implementar em app/services/links/path_finder.rb
```

---

### 4.3 Tags (N:N)

```
tags
  id          UUID PK
  name        string UNIQUE NOT NULL
  color_hex   string (ex: #22c55e)
  icon        string (nome do ícone — opcional)
  tag_scope   enum (note, link, both) DEFAULT both
  created_at  timestamp

note_tags (join)
  note_id     UUID FK → notes
  tag_id      UUID FK → tags
  created_at  timestamp
  PRIMARY KEY (note_id, tag_id)

link_tags (join)
  note_link_id UUID FK → note_links
  tag_id       UUID FK → tags
  created_at   timestamp
  PRIMARY KEY (note_link_id, tag_id)
```

**Regras:**
- Tags em links controlam cor/estilo de aresta no grafo (ex: dashed, weight)
- Tags são chips filtráveis na UI

---

### 4.4 Armazenamento de Mídia — Interface Agnóstica

Active Storage com serviço local por padrão. A interface agnóstica permite trocar o backend
de armazenamento editando apenas `config/storage.yml` e uma ENV, sem alterar código da aplicação.

```yaml
# config/storage.yml

local:
  service: Disk
  root: <%= Rails.root.join("storage") %>

# Alternativas futuras — descomentar conforme necessário:
# amazon:
#   service: S3
#   ...
# minio:
#   service: S3
#   endpoint: http://minio:9000
#   ...
# sftp_custom:
#   service: Mirror  # ou custom service
#   ...
```

```ruby
# config/environments/production.rb
config.active_storage.service = ENV.fetch("STORAGE_SERVICE", "local").to_sym
```

**Regras:**
- Padrão: `local` — armazenamento em volume Docker (`storage_data`)
- Troca de backend: apenas alterar `STORAGE_SERVICE` ENV e credenciais
- Sem S3 por padrão — latência local é aceitável para uso self-hosted
- `NoteRevision has_many_attached :assets`

---

### 4.5 TTS — ElevenLabs e Fish Audio

```
note_tts_assets
  id                    UUID PK
  note_revision_id      UUID FK → note_revisions
  language              string NOT NULL (ex: pt-BR, en-US, zh-CN, ja-JP, ko-KR)
  voice                 string NOT NULL (id/nome do provider)
  provider              string NOT NULL (elevenlabs, fish_audio, openai)
  model                 string
  format                string (mp3, wav, opus) DEFAULT mp3
  text_sha256           string NOT NULL
  settings_hash         string NOT NULL (hash de speed, stability, similarity_boost, etc.)
  duration_ms           integer
  is_active             boolean DEFAULT true (false = descartado pelo usuário)
  created_at            timestamp
  [has_one_attached :audio via Active Storage]
```

**Cache key:** `(text_sha256, language, voice, provider, model, settings_hash)`
Se já existe registro ativo com essa chave → não chama API.

**Fluxo de geração:**
1. Usuário abre nota → botão "Gerar Áudio"
2. Seleciona: idioma (pré-preenchido com `detected_language`), provider, voz, configurações
3. Sistema verifica cache pela chave — se existe, usa o existente
4. Se não existe → chama API → salva arquivo via Active Storage → cria `note_tts_asset`
5. Player embutido na nota para reprodução

**Fluxo de regeção:**
1. Usuário ouve e não aprova o áudio → clica "Gerar Novo"
2. `is_active = false` no registro atual (mantém histórico)
3. Abre dialog para escolher novo provider/voz/configurações
4. Gera novo `note_tts_asset` com `is_active = true`

**Providers TTS:**

| Provider | Capability | Notas |
|---|---|---|
| ElevenLabs | TTS de alta qualidade | Suporta pt-BR, en, zh, ja, ko |
| Fish Audio | TTS alternativo | Bom para CJK |
| OpenAI TTS | TTS básico | Fallback |

**Suporte a idiomas CJK:**
- Mandarim: `zh-CN`, `zh-TW`
- Japonês: `ja-JP`
- Coreano: `ko-KR`
- Editor CodeMirror: garantir que `contenteditable` e input method (IME) funcionem corretamente
- Fonte: incluir fallback para CJK no Tailwind (`font-sans` já inclui via system fonts)
- Busca: `pg_search` com `tsvector` suporta CJK via extensão `zhparser` (Mandarim) ou tokenização por caractere

### 4.5.1 Compartilhamento por Mount para Kokoro e Montreal Forced Aligner

Kokoro e Montreal Forced Aligner devem ser tratados como integrações futuras que compartilham arquivos com o NeuraMD por **mount de host**, não por cópia ad hoc.

**Objetivo:**

- manter assets, cache intermediário e saídas acessíveis por múltiplos serviços
- evitar duplicação de áudio/transcrições/alinhamentos
- permitir inspeção manual simples no host
- facilitar backup de toda a cadeia de IA/TTS/alinhamento

**Recomendação de infraestrutura:**

- criar uma partição ou volume dedicado no host
- montar em um caminho fixo, por exemplo: `/mnt/neuramd-share`
- expor esse caminho para a app e futuras ferramentas por bind mount

**Layout sugerido da repartição compartilhada:**

```text
/mnt/neuramd-share/
  exchange/
    inbound/
    outbound/
  ollama/
    cache/
  kokoro/
    input/
    output/
    voices/
    cache/
  mfa/
    input/
    output/
    dictionaries/
    acoustic_models/
    temp/
  tts/
    rendered/
    rejected/
  alignments/
    textgrids/
    json/
```

**Convenções de uso:**

- `exchange/`:
  - zona neutra para interoperabilidade entre serviços
  - útil para jobs assíncronos e inspeção manual
- `kokoro/input` e `kokoro/output`:
  - entrada e saída cruas de síntese local
- `mfa/input` e `mfa/output`:
  - corpus temporário, transcrições e alinhamentos gerados
- `tts/rendered`:
  - artefatos finais aprovados para associação com `note_tts_assets`
- `tts/rejected`:
  - saídas descartadas que ainda valem auditoria técnica
- `alignments/textgrids`:
  - formato principal para Montreal Forced Aligner

**Regras para implementação futura:**

- o NeuraMD continua usando Active Storage para o artefato final persistido na aplicação
- Kokoro/MFA operam sobre o mount compartilhado como workspace
- jobs devem mover ou copiar para Active Storage apenas o resultado final aceito
- nomes de arquivos devem preferir UUID da nota/revisão e timestamps
- nenhum serviço deve assumir caminhos relativos frágeis fora de `SHARED_AI_ROOT`

**ENV base para essa estratégia:**

```bash
SHARED_AI_ROOT=/mnt/neuramd-share
KOKORO_ROOT=/mnt/neuramd-share/kokoro
MFA_ROOT=/mnt/neuramd-share/mfa
TTS_RENDER_ROOT=/mnt/neuramd-share/tts/rendered
ALIGNMENT_ROOT=/mnt/neuramd-share/alignments
```

---

### 4.6 IA Plugável (texto)

```
ai_providers
  id                  UUID PK
  name                string (openai, anthropic, azure_openai, local, ollama)
  enabled             boolean DEFAULT false
  base_url            string
  default_model_text  string
  config              jsonb (parâmetros não sensíveis)
  created_at          timestamp

# Segredos NUNCA no banco — via ENV:
# AI_OPENAI_API_KEY, AI_ANTHROPIC_API_KEY
# TTS_ELEVENLABS_API_KEY, TTS_FISH_AUDIO_API_KEY

ai_requests (auditoria)
  id                  UUID PK
  note_revision_id    UUID FK → note_revisions
  provider            string
  capability          enum (suggest, rewrite, grammar_review, tts)
  request_hash        string
  prompt_summary      text (opcional — cuidado com privacidade)
  response_summary    text (opcional)
  tokens_in           integer
  tokens_out          integer
  cost_estimate       numeric
  created_at          timestamp
```

**Decisões de implementação da Fase 5:**

- Providers de IA de texto vivem em `app/services/ai/`
- Seleção de provider:
  - `ENV["AI_PROVIDER"]` pode forçar provider específico
  - `ENV["AI_ENABLED_PROVIDERS"]` pode limitar a lista
  - `ai_providers.enabled` complementa a configuração persistida
- Secrets ficam **somente em ENV**
- O modal de IA no editor deve operar em dois escopos:
  - seleção ativa do CodeMirror
  - documento inteiro quando não há seleção
- Toda chamada bem-sucedida deve gerar um registro em `ai_requests`
- `grammar_review`, `suggest` e `rewrite` compartilham a mesma infraestrutura e mudam apenas o prompt/capability
- O resultado de IA **não cria checkpoint automaticamente**
  - primeiro aplica no editor
  - depois o usuário decide salvar como draft/checkpoint no fluxo normal

**Providers iniciais da Fase 5:**

| Provider | Status | Observação |
|---|---|---|
| OpenAI | Inicial | endpoint compatível com `/chat/completions` |
| Anthropic | Inicial | endpoint `/messages` |
| Ollama | Inicial | execução local para uso self-hosted |
| Azure OpenAI | Inicial | via compatibilidade OpenAI com `base_url` específico |
| Local OpenAI-compatible | Inicial | ex: LM Studio / vLLM / outros gateways |

---

## 5. Busca

- **Títulos:** `pg_trgm` (trigram) — rápido para strings curtas
- **Conteúdo:** `tsvector('simple')` + `pg_trgm similarity` em `content_plain`
- **CJK:** fallback por trigram/similarity em `content_plain`
- **Fuzzy finder / busca principal:** serviço Rails único com ranking híbrido (ILIKE + trigram + tsvector)
- **Regex no conteúdo:** com paginação, timeout e limite de N resultados
- Indexes: `GIN` em `content_plain` para `tsvector`; `GIN` em `title` para `trgm`

---

## 6. Grafo Web (Fase 4)

- A especificação detalhada do grafo vive em `GRAFO.md` e deve ser tratada como fonte de verdade
- O estado atual de `/graph` e `/api/graph` deve ser considerado descartável se divergir de `GRAFO.md`
- Backend do grafo em Rails; frontend do grafo em JavaScript no browser integrado à página Rails
- Endpoint de dados do grafo deve retornar dataset normalizado (`notes`, `links`, `tags`, `noteTags`, `linkTags`)
- Visualização com Sigma.js + Graphology
- Filtros: `hier_role`, tag, profundidade máxima, foco por nó, modos de destaque por tags
- Tooltip HTML persistente no clique e transitório no hover
- Navegação por clique para abrir a nota
- Arestas com semântica visual por `hier_role`
- Insights futuros via CTE:
  - Notas mais referenciadas
  - Clusters de temas
  - Notas órfãs
  - Caminho mais curto entre duas notas

---

## 7. Editor Web (CodeMirror 6 — base FrankMD)

**Portar do FrankMD (adaptar para banco, não filesystem):**
- Syntax highlight Markdown + fenced code blocks com autocomplete de linguagem
- Atalhos: bold/italic/inline code/heading/list
- Find/replace dialog (client-side)
- Jump to line dialog
- Emojis (:smile:)
- Stats: palavras/linhas, linha atual
- Typewriter mode
- Scroll sync editor ↔ preview (debounce)
- Offline detection + content loss protection
- Themes dark/light
- Cheatsheet Markdown
- Code block dialog com autocomplete de linguagem
- Grid de imagens + upload/insert (adaptar de filesystem para Active Storage)
- Embed YouTube com allowlist
- IA: grammar checking + sugestão (adaptar providers)

**Adições do NeuraMD:**
- **Estratégia de save em três camadas:**
  - `localStorage` (debounce 3s, client-side only) — proteção contra crash/tab fechada, sem requests
  - Draft no servidor (debounce ~60s) — `POST /notes/:slug/draft`, cria `note_revision` com `kind: draft`; deleta o draft anterior da mesma nota; não aparece no histórico
  - Checkpoint manual (botão "Salvar" no canto superior direito) — `POST /notes/:slug/checkpoint`, cria `note_revision` com `kind: checkpoint`; permanente; aparece no histórico
- **Histórico de versões:** timeline de checkpoints com diff visual; botão "Restaurar" cria novo checkpoint com conteúdo histórico
- **Wiki-links `[[Título|uuid]]`** — autocomplete ao digitar `[[`, navegação com setas, inserção com Enter/Tab, link quebrado = fundo vermelho
- **Sincronização de links em checkpoints** — `Links::SyncService` extrai wiki-links do markdown e atualiza `note_links` (create/delete, sem duplicatas por `(src, dst)`)
- **Backlinks no preview** — rodapé com lista de notas que linkam para esta nota
- Preview HTML via marked.js client-side (instantâneo, sem request)
- Botão "Gerar Áudio" → abre dialog TTS com idioma/provider/voz
- Player de áudio embutido quando `note_tts_asset` existe
- Suporte IME para input CJK (Mandarim/Japonês/Coreano)

---

## 8. Segurança

- `content_markdown` criptografado via AR Encryption
- Chaves via ENV ou Rails credentials (nunca hardcoded)
- Autenticação: Devise
- Autorização: Pundit
- Cookies seguros + CSRF protection (Rails padrão)
- Rate limiting opcional: Rack::Attack
- Disco criptografado (LUKS) recomendado no servidor
- Tokens de IA e TTS: apenas via ENV, nunca no banco

---

## 9. Princípios de Arquitetura

- **Controllers magros** — regras em Services e Policies
- **Services por domínio:** `app/services/notes/`, `app/services/links/`, `app/services/search/`, `app/services/ai/`, `app/services/tts/`
- **Links são entidades de primeira classe** — direção sempre declarada pela nota src
- **Backlinks são queries** — não entidades duplicadas
- **IA é plugável** — trocar provider sem reescrever app
- **TTS é cacheável** — nunca re-gerar se hash já existe; usuário descarta, não apaga
- **Armazenamento é agnóstico** — trocar de local para qualquer outro via ENV + `storage.yml`
- **Notas são identidade** — conteúdo é revisionado, nunca sobrescrito

---

## 10. Estrutura do Projeto

```
app/
  models/
  services/
    notes/
    links/
      path_finder.rb
    search/
    ai/
    tts/
      elevenlabs_provider.rb
      fish_audio_provider.rb
      base_provider.rb
  javascript/
    controllers/   (Stimulus)
    editor/        (CodeMirror 6)
config/
  storage.yml      (backends de armazenamento)
docs/
  architecture.md
  adr/
  deploy.md
spec/
  models/
  services/
  system/
  requests/
```

---

## 11. Plano Incremental de Execução

### Fase 0 — Fundação *(define o esqueleto)*
- [x] Rails 8 + PostgreSQL + Docker
- [x] Devise auth + Tailwind base (com font fallback CJK)
- [x] Modelos: `notes`, `note_revisions`, `note_links`, `tags`, joins
- [x] Active Storage configurado com serviço local + `STORAGE_SERVICE` ENV
- [x] AR Encryption configurado (chaves via ENV)
- [x] Testes base (RSpec) + CI
- **Entrega:** CRUD básico de nota com revisão e anexos

### Fase 1 — Editor + Preview *(core de uso)*
- [x] Portar CodeMirror 6 do FrankMD (adaptar para banco)
- [x] Preview HTML client-side (CodeMirror + Stimulus)
- [x] Autosave com política (debounce + threshold) → `note_revisions`
- [x] Find/replace, jump-to-line, atalhos, typewriter mode
- [x] Offline detection + content loss protection
- [x] Suporte IME para input CJK
- **Entrega:** editor usável no dia-a-dia

### Fase 2 — Links Semânticos + Tags + Versionamento *(diferencial)*

#### 2a — Versionamento com save em 3 camadas
- [x] Migração: adicionar `revision_kind enum (draft, checkpoint)` em `note_revisions`
- [x] `POST /notes/:slug/draft` — upsert de draft (deleta draft anterior, cria novo)
- [x] `POST /notes/:slug/checkpoint` — cria checkpoint permanente + sincroniza links
- [x] Botão "Salvar" (canto superior direito no editor) → dispara checkpoint
- [x] Draft automático no servidor: debounce 60s no `autosave_controller.js`
- [x] localStorage continua em 3s (crash protection, sem mudança)
- [x] Timeline de checkpoints: `GET /notes/:slug/revisions` (somente `kind: checkpoint`)
- [x] Visualização de revisão histórica: `GET /notes/:slug/revisions/:id`
- [x] Restaurar revisão: `POST /notes/:slug/revisions/:id/restore` → novo checkpoint
- [x] Specs: draft upsert, checkpoint persist, restore flow

#### 2b — Wiki-Links semânticos com autocomplete
- [x] `GET /notes/search?q=:query` — endpoint JSON `{id, title, slug}` para autocomplete
- [x] `Links::ExtractService` — extrai `[[Título|uuid]]` do markdown, retorna array de UUIDs
- [x] `Links::SyncService` — diff entre links extraídos e `note_links` existentes; cria/deleta; sem duplicatas por `(src_note_id, dst_note_id)`; só roda em checkpoints
- [ ] ~~`Links::TitleSyncService`~~ — não necessário; Display Text é livre e não rastreia o título da nota
- [x] CodeMirror extension: detecta `[[`, abre dropdown Stimulus com sugestões via fetch, navega com `↑`/`↓`, insere com `Enter`/`Tab`, fecha com `Esc`
- [x] Decoração de link quebrado: UUID não encontrado no DB → classe CSS `wikilink-broken` (fundo vermelho) no editor via CodeMirror ViewPlugin
- [x] Preview: render `[[Título|uuid]]` como `<a href="/notes/slug">Título</a>` (client-side no preview controller)
- [x] Preview: se UUID inexistente, render como `<span class="wikilink-broken">Título</span>`
- [x] Backlinks no preview: seção no rodapé com notas src linkando para a nota atual
- [x] Specs: ExtractService, SyncService, TitleSyncService, endpoint search, render com links

#### 2c — Tags
- [x] API Tags: `GET/POST/DELETE /tags` — JSON, Pundit auth
- [x] API LinkTags: `POST/DELETE /link_tags` { note_link_id, tag_id } — N:N, idempotent
- [x] Tag sidebar (colapsável, esquerda do editor) — Stimulus `tag_sidebar_controller`
- [x] **Link mode** (cursor dentro de `[[Display|uuid]]`): múltiplas tags ativas simultaneamente para o mesmo link (N:N checkboxes); clicar numa tag adiciona/remove; tags checked flutuam ao topo
- [x] **Global mode** (cursor fora de link): uma tag ativa por vez; clicar destaca NO PREVIEW todos os links com essa tag; clicar de novo desativa
- [x] `wikilink:cursor` event dispatch: codemirror_controller detecta posição do cursor e emite evento; tag_sidebar_controller reage mudando de modo
- [x] `GET /notes/:slug/link_info?dst_uuid=` — retorna { link_id, tags } para o link focado
- [x] `link-tags-data` JSON pré-carregado no `data-` attribute da view — evita request extra para highlight global
- [x] Specs: tag CRUD, link_tag N:N, idempotência, toggle, highlight semântico

- **Entrega:** links semânticos automáticos via markup, histórico de checkpoints navegável, tags em links

### Fase 3 — Busca
- [x] `pg_trgm` em títulos
- [x] Busca em conteúdo com `tsvector` + fallback trigram para CJK
- [x] Fuzzy finder dialog (client-side)
- [x] Busca por regex com limites (paginação, timeout, max N)
- [x] Indexes GIN
- **Entrega:** produtividade real

### Fase 4 — Grafo Web
- [x] Revisar a feature do grafo partindo de `GRAFO.md`, sem reaproveitar por inércia a implementação atual
- [x] Novo `GET /api/graph` com dataset normalizado (`notes`, `links`, `tags`, `noteTags`, `linkTags`)
- [x] Nova página `GET /graph` integrada ao Rails e desacoplada da UI atual
- [x] Visualização JS com Sigma.js + Graphology
- [x] Custom edge renderer para seta em `source` ou `target` e gap assimétrico
- [x] Filtros (`hier_role`/tag/profundidade), foco por nó e modos de destaque
- [x] Tooltip HTML persistente/transitório
- [x] Navegação por clique
- [x] CTEs recursivas para insights (descendentes, órfãs, caminho)
- [x] Tags em notas (`note_tags` join) visíveis também no nível do nó
- [x] Filtro por tag na listagem de notas
- **Entrega:** grafo útil e navegável

### Fase 5 — IA Plugável (texto)
- [x] Interface `Ai::Provider` (adapter pattern) — base do FrankMD
- [x] Sugestão de texto
- [x] Revisão gramatical com preview de diff antes de aplicar
- [x] `ai_requests` para auditoria
- [x] Feature flags via ENV (ativar/desativar providers)
- [x] Rewrite com a mesma infraestrutura de diff/apply
- [x] Specs de service para seleção de provider, prompt e falhas remotas
- [x] Expor escolha explícita de provider/model no UI quando necessário
- [x] Marcar revisões aceitas via IA com metadado mais explícito no fluxo de checkpoint
- [x] Roteamento automático de modelo para Ollama com override manual na UI
- **Entrega:** IA controlável e segura

#### Fase 5 — O que portar do FrankMD e o que não portar

**Portar quase direto:**
- dialog de diff lado a lado
- overlay de processamento
- controller Stimulus para abrir modal, chamar endpoint e aplicar o resultado
- utilitário de diff puro em JavaScript

**Portar adaptando:**
- controller HTTP de IA
- service de roteamento de provider
- service de roteamento de model por capability/tamanho quando o provider for `ollama`
- prompts para grammar/suggest/rewrite

**Não portar:**
- leitura de arquivo em disco como entrada principal
- configuração `.fed`
- qualquer decisão que ignore `ai_requests`
- qualquer fluxo que aplique resultado direto no storage sem passar pelo editor

#### Fase 5 — Matriz mínima de testes

Toda evolução da fase 5 deve manter esta matriz:

- `spec/requests/ai_spec.rb`
  - status do provider
  - contrato do endpoint de review
  - erros de validação
  - criação de `ai_requests`
- `spec/services/ai/*`
  - prompt por capability
  - seleção de provider por ENV/DB
  - tratamento de timeout/erro do provider
  - parsing da resposta de cada provider
- `spec/system/ai_review_spec.rb`
  - abrir modal pelo toolbar
  - processar seleção
  - processar documento inteiro
  - aplicar texto no CodeMirror
  - exibir fallback de “IA não configurada”
- testes futuros de job
  - enfileirar requisições para `AIrch`
  - persistir estado `queued/running/succeeded/failed`
  - reprocessar falhas transitórias de rede

#### Fase 5 — Benchmarks `AIrch` CPU-only (2026-03-20)

Benchmarks reais no host `AIrch` indicam:

- evitar `qwen3*` e `qwen3.5*` como default nesse host; custo alto e recorrência de respostas vazias por `thinking/length`
- `grammar_review` curto: `qwen2.5:0.5b`
- `grammar_review` maior: `qwen2.5:1.5b`
- `suggest` curto: `qwen2:1.5b`
- `suggest` maior: `qwen2.5:3b`
- `rewrite` curto: `qwen2.5:1.5b`
- `rewrite` maior e quando qualidade pesa mais que latência: `llama3.2:3b`
- tradução `pt -> en` curta: `qwen2:1.5b`
- tradução `pt -> en` maior ou mais crítica: `qwen2.5:3b`

Essas decisões devem permanecer em ENV e em service de roteamento, nunca hardcoded apenas na UI.

### Fase 5.5 — Tradução Assistida com Nota Irmã
- [ ] Nova capability `translate`
- [ ] Criar nota irmã (`brother`) a partir de uma nota existente para armazenar a tradução
- [ ] Vincular idioma de origem/destino na nota e na request
- [ ] UI para escolher idioma alvo e confirmar criação da nota irmã
- [ ] Fluxo inicial priorizando `pt-BR -> en`
- [ ] Benchmarks adicionais com textos maiores e Markdown real
- **Entrega:** tradução controlada, auditável e sem misturar idiomas na mesma nota

### Fase 6 — TTS com Cache (ElevenLabs + Fish Audio)
- [ ] `Tts::BaseProvider` interface + `ElevenLabsProvider` + `FishAudioProvider`
- [ ] `note_tts_assets` com cache por hash
- [ ] Detecção automática de idioma da nota (`detected_language`)
- [ ] UI: dialog "Gerar Áudio" (idioma/provider/voz/configurações)
- [ ] Player embutido na nota
- [ ] Fluxo de rejeição: "Gerar Novo" com novas configurações
- [ ] Suporte a zh-CN, zh-TW, ja-JP, ko-KR
- [ ] Definir bind mounts de workspace para Kokoro e MFA usando `SHARED_AI_ROOT`
- [ ] Padronizar nomeação de artefatos compartilhados por `note_revision_id`
- **Entrega:** áudio eficiente e multi-idioma

#### Fase 6 — Preparação de Infra para Ferramentas Locais

Mesmo antes da integração completa com Kokoro ou MFA, a infraestrutura deve ser pensada para:

- mount estável e previsível
- artefatos legíveis fora do container
- possibilidade de executar ferramentas localmente no host ou em containers separados

**Bind mount recomendado em compose futuro:**

```yaml
services:
  app:
    volumes:
      - ${SHARED_AI_ROOT:-/mnt/neuramd-share}:/mnt/neuramd-share

  kokoro:
    volumes:
      - ${SHARED_AI_ROOT:-/mnt/neuramd-share}:/mnt/neuramd-share

  mfa:
    volumes:
      - ${SHARED_AI_ROOT:-/mnt/neuramd-share}:/mnt/neuramd-share
```

Esse padrão evita drift entre caminhos internos dos serviços.

**Imagens base atualmente escolhidas para alinhamento inicial:**

- Kokoro: `ghcr.io/remsky/kokoro-fastapi-cpu:v0.2.4`
- Montreal Forced Aligner: `mmcauliffe/montreal-forced-aligner:latest`

Essas escolhas devem ser revisitadas quando houver benchmark real de CPU/GPU, throughput e footprint no host `AIrch`.

### Fase 7 — Polimento Editor e UX
- [ ] Themes (dark + custom) — base FrankMD
- [ ] Font dialog, zoom refinado
- [ ] Grid de imagens melhorado + upload/insert via Active Storage
- [ ] Embed YouTube dialog
- [ ] Histórico de revisões com diff visual
- **Entrega:** editor com cara de app

### Fase 8 — iPad (futuro)
- [ ] API REST estabilizada
- [ ] Endpoints para assets e revisões
- [ ] Autenticação via token
- [ ] Cliente iPad consumindo (detalhar quando chegar aqui)

---

## 12. Decisões que Não Podem ser Adiadas

| Decisão | Motivo |
|---|---|
| N:N tags desde o início | Refatorar depois é custoso |
| Revisões como tabela separada | Nunca sobrescrever conteúdo |
| Active Storage com ENV desde o início | Trocar backend sem alterar código |
| IA com interface provider + feature flag | Trocar provider sem reescrever |
| Cache TTS por hash + `is_active` | Não gastar tokens repetindo; manter histórico |
| AR Encryption configurada | Difícil adicionar depois com dados existentes |
| UUIDs como PKs | Melhor para APIs e futura distribuição |
| Links sempre src-declarado | Semântica clara; backlinks são queries |
| `detected_language` na nota | TTS precisa do idioma; CJK precisa de tratamento especial |
| Font fallback CJK no Tailwind | Mandarim/Japonês/Coreano desde o início |
| `revision_kind (draft/checkpoint)` | Separar salvamento automático de versionamento real; evitar explosão de revisões |
| Draft = upsert (1 por nota) | Horas editando a mesma nota geram 1 draft, não centenas |
| Links sincronizados apenas em checkpoints | Evitar churn no DB; links refletem versões consolidadas |
| UUID como referência do link, Display Text livre | Robustez a renomear notas; usuário controla texto exibido; UUID nunca muda |
| `f:/c:/b:` prefixos de hier_role no UUID | Sem sintaxe extra no Display Text; role embutida no campo de referência |
| Tooltip no preview = título real da nota | Display Text pode divergir do título; tooltip sempre mostra o título atual do DB |
| Sem TitleSyncService | Display Text é livre — não há título para propagar; simplifica drasticamente |
| Grafo especificado em `GRAFO.md` | Evitar drift entre visão de produto e implementação da feature |

---

## 13. Docker Compose (referência inicial)

```yaml
services:
  app:
    build: .
    depends_on: [postgres, redis]
    environment:
      - DATABASE_URL
      - SECRET_KEY_BASE
      - RAILS_MASTER_KEY
      - STORAGE_SERVICE=local
      - AI_OPENAI_API_KEY
      - AI_ANTHROPIC_API_KEY
      - TTS_ELEVENLABS_API_KEY
      - TTS_FISH_AUDIO_API_KEY
      - ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY
      - ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY
      - ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT
    volumes:
      - storage_data:/rails/storage
    ports:
      - "3000:80"

  postgres:
    image: postgres:16
    environment:
      - POSTGRES_DB
      - POSTGRES_USER
      - POSTGRES_PASSWORD
    volumes:
      - db_data:/var/lib/postgresql/data

  redis:
    image: redis:7-alpine
    volumes:
      - redis_data:/data

volumes:
  db_data:
  storage_data:
  redis_data:
```

---

## 14. Prompt Inicial para Claude Code

Use este prompt ao iniciar o projeto no CLI:

```
Estou construindo uma aplicação Rails 8 de notas self-hosted chamada "NeuraMD".
Leia o arquivo PLAN.md neste diretório — ele descreve a arquitetura e o plano incremental.

Referência de implementação do editor: ../FrankMD (disponível localmente ao lado deste projeto)
(Rails 8 + CodeMirror 6 + Hotwire — portar o máximo de funcionalidades de usabilidade,
adaptando para banco de dados PostgreSQL e Active Storage local em vez de filesystem + S3)

Comece pela Fase 0 do PLAN:
1. Scaffold Rails 8 com PostgreSQL e UUID como PK padrão
2. Docker + docker-compose com postgres e redis
3. Devise para autenticação
4. Tailwind CSS com font fallback CJK (Mandarim/Japonês/Coreano)
5. Modelos: Note, NoteRevision, NoteLink, Tag, NoteTag, LinkTag, NoteTtsAsset
   - Seguir exatamente o schema da seção 4 do SPEC
   - UUIDs como PKs
   - AR Encryption em NoteRevision.content_markdown
6. Active Storage com serviço local + STORAGE_SERVICE ENV para troca futura
7. RSpec configurado com FactoryBot

Siga as convenções: controllers magros, services em app/services/,
StandardRB para linting.

Não implemente o editor ainda — foque em ter a fundação sólida com testes.
```

---

## 15. Ambiente de Desenvolvimento — Rede Local (192.168.100.0/24)

### Acesso por rede LAN

- O servidor Rails é iniciado com `bin/rails server -b 0.0.0.0` (já configurado no `Procfile.dev`)
- **Nunca vincular apenas a `127.0.0.1`** — perde-se acesso SSH/remoto ao subir os processos
- Acesso à aplicação: `http://192.168.100.X:3000` (IP do servidor na rede local)
- Docker: portas expostas em `0.0.0.0` para aceitar conexões da subnet

**Configuração obrigatória em development:**

```ruby
# config/environments/development.rb
config.hosts << /\A192\.168\.100\.\d+\z/   # aceita qualquer IP da subnet
```

Sem isso, Rails 8 bloqueia requests com `BlockedHost` error vindo de IPs da rede.

### Testes de Aceitação

- **Acesso de validação:** feito a partir de outro dispositivo na rede `192.168.100.0/24`
- **NÃO usar localhost** para validação — testar sempre pelo IP real do servidor
- Isso torna observável via DevTools a diferença real entre client-side e server-side

### Distinguindo Client-Side vs Server-Side via Rede

Testar pelo IP real (não `localhost`) expõe o comportamento de rede no DevTools:

| Comportamento | O que observar na aba Network |
|---|---|
| **Client-side** (ex: preview Markdown via marked.js) | Instantâneo — nenhum request visível |
| **Server-side** (ex: autosave → `POST /notes/:slug/autosave`) | Request `XHR/Fetch` visível com latência real |
| **Turbo Frame** (ex: revisões, grafo) | Request `Doc` visível, resposta HTML parcial |
| **Offline detection** | Desconectar dispositivo de teste → banner aparece sem acessar app |

**Checklist de validação por funcionalidade:**
- Preview HTML: deve ser instantâneo (client-side via marked.js) — latência = regressão para server-side
- Autosave: deve gerar `POST` visível no DevTools a cada disparo (3s debounce)
- Revisões: `GET /notes/:slug/revisions` visível ao abrir o painel
- Offline banner: sem request de rede — apenas Event de conectividade do browser

### Regras para Processos Dev

- `bin/dev` (Foreman com Procfile.dev): Rails vincula em `0.0.0.0` — correto
- PostgreSQL e Redis: aceitar conexões apenas de `127.0.0.1` (interno ao servidor) — não expor na LAN
- **Não alterar bind de PostgreSQL/Redis para `0.0.0.0`** — expõe dados sensíveis na rede

---

## 16. Política de Testes

### 16.1 Filosofia — TDD Estrito

**Toda funcionalidade nova começa com testes.** Nenhum código de produção é escrito antes que haja pelo menos um teste falhando que descreve o comportamento esperado.

Fluxo obrigatório:
1. **Red** — escrever o(s) teste(s) que descreve(m) o comportamento desejado; confirmá-los falhando
2. **Green** — implementar o mínimo necessário para os testes passarem
3. **Refactor** — limpar o código sem quebrar os testes

**Bugs reportados seguem o mesmo fluxo:** antes de qualquer fix, escrever um teste que reproduz o comportamento indesejado e confirmá-lo falhando. Só então corrigir o bug. O teste que falhou é a garantia de não-regressão.

### 16.2 Pirâmide de Testes

```
          ┌───────────────────────┐
          │   E2E / Aceitação     │  Playwright (MCP) — poucos, críticos
          │   (fluxos completos)  │  Capybara + Cuprite — sistema + JS
          ├───────────────────────┤
          │   Integração          │  RSpec request specs, service specs
          │   (controllers, API)  │  FactoryBot + DatabaseCleaner
          ├───────────────────────┤
          │   Unitários           │  RSpec model/service specs
          │   (models, services)  │  Rápidos, sem browser, sem DB se possível
          └───────────────────────┘
```

Princípio: **a maioria dos testes deve ser unitária/integração** (rápida, barata). E2E cobre apenas os fluxos críticos que não podem ser validados sem browser.

### 16.3 Stack de Testes

#### Testes Ruby (backend + integração)
- **RSpec** — framework principal
- **FactoryBot** — fixtures declarativas
- **DatabaseCleaner** — truncation para system specs (browser vê dados commitados), transaction para o resto
- **Shoulda Matchers** — validações de modelo
- **Capybara + Cuprite** — system specs com JS real (Chromium via CDP, sem ChromeDriver)

#### Testes E2E (fluxos completos, cross-layer)
- **Playwright** via `@playwright/mcp` — testes E2E orquestrados pelo Claude Code via MCP
  - Usado quando: validar fluxo completo de usuário end-to-end (login → criar nota → salvar → verificar)
  - Vantagem: Claude Code pode inspecionar e interagir com o browser em tempo real durante desenvolvimento
  - Configurar: `npx @playwright/mcp@latest` (sem instalação permanente necessária)
- **Capybara + Cuprite** — system specs integrados no RSpec (`spec/system/`)
  - Usado quando: testar comportamento JS específico em contexto Rails (Stimulus controllers, Hotwire)
  - Vantagem: acesso direto a factories, helpers Rails, DatabaseCleaner integrado
  - Driver: `:cuprite` (Ferrum/CDP) — `HEADED=1 bundle exec rspec` para abrir browser visível

#### Escolha entre Playwright MCP e Capybara/Cuprite

| Cenário | Ferramenta |
|---|---|
| Novo fluxo de usuário (bug reprodução ou feature) | Playwright MCP — exploração rápida |
| Teste permanente no CI | Capybara + Cuprite em `spec/system/` |
| Comportamento JS de Stimulus controller isolado | Capybara + Cuprite |
| Fluxo multi-página com sessão (login→ação→logout) | Playwright MCP para explorar, depois Cuprite para fixar |
| Validar comportamento indesejado reportado | Cuprite — escrever spec que falha, depois fixar |

### 16.4 Regras de Escrita de Testes

#### Estrutura de arquivos
```
spec/
  models/           → unitários de modelo (validações, escopos, métodos)
  services/         → unitários de service (lógica de domínio)
  requests/         → integração HTTP (controllers, autenticação, JSON API)
  system/           → E2E com browser (JS, Stimulus, fluxos completos)
  javascript/       → lógica JS pura portada para Ruby (algoritmos, regex)
  support/
    cuprite.rb      → configuração Cuprite
    ar_encryption.rb → chaves de teste
    factories/      → FactoryBot factories
```

#### Nomenclatura e organização
- Descrever **comportamento**, não implementação: `"salva draft ao perder foco"` não `"chama DraftService"`
- Um `describe` por conceito/contexto; `it` por caso concreto
- Usar `let!` para dados que o browser precisa ver (já commitados antes do JS rodar)
- Evitar `sleep` fixo — usar `have_css(..., wait: N)` e `have_text(..., wait: N)` do Capybara

#### Reprodução de bug (protocolo obrigatório)
```
1. Criar spec em spec/system/ ou spec/requests/ que descreve o comportamento indesejado
2. Rodar e confirmar que FALHA com a mensagem esperada
3. Commitar o teste falhando (opcional, mas preferível)
4. Implementar o fix
5. Confirmar que o teste passa
6. Rodar suite completa — nenhuma regressão
```

**Nunca corrigir um bug sem antes ter um teste que o reproduz.**

#### Testes Cuprite — gotchas e boas práticas
- Teclas de seta: usar `:down`, `:up`, `:left`, `:right` (não `:arrow_down` etc.)
- Teclas de controle: `[:control, :home]`, `[:control, :end]` (símbolos, não strings)
- CSS `text-transform: uppercase` → usar regex case-insensitive: `text: /global/i`
- `let!` (não `let`) para dados que devem existir no DB antes da visita à página
- Capturar console JS: sobrescrever `console.log` via `page.execute_script` antes da ação; ler com `page.evaluate_script("window.__consoleLogs")`
- `js_errors: true` no driver para surfaçar erros JS não tratados durante desenvolvimento

#### Diagnóstico de falhas em system specs
Quando um system spec falha de forma misteriosa (evento disparado mas DOM não atualiza):
1. Adicionar `console.log` temporários nos Stimulus controllers (fonte JS em `app/javascript/`)
2. Capturar via `page.execute_script` que instala collector antes da ação
3. Ler com `page.evaluate_script("window.__consoleLogs")`
4. Remover logs após identificar e corrigir o problema

### 16.5 Comandos de Teste

```bash
# Suite completa
bundle exec rspec

# Apenas system specs (browser)
bundle exec rspec spec/system/

# System spec com browser visível (debug)
HEADED=1 bundle exec rspec spec/system/wikilink_editor_spec.rb

# Spec específico
bundle exec rspec spec/system/wikilink_editor_spec.rb:39

# Playwright MCP (via Claude Code — sem instalação permanente)
npx @playwright/mcp@latest
```

### 16.6 Cobertura Mínima por Camada

Antes de considerar uma funcionalidade completa, deve haver:

| Camada | O que cobrir |
|---|---|
| Model | Validações, escopos, callbacks, associações críticas |
| Service | Happy path + casos de erro + edge cases do domínio |
| Request/Controller | Autenticação (401), autorização (403), sucesso (2xx), erro (422) |
| System (JS) | Fluxo principal do usuário + regressões reportadas |

---

*Última atualização: 2026-03-06 (Política de testes adicionada)*
*NeuraMD — Stack: Rails 8 · PostgreSQL 16 · Hotwire · CodeMirror 6 · Docker*
