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

## 1.1 Prioridades Atuais

As prioridades correntes do produto, acima de polimento e expansões laterais, são:

1. **Link ativo de grafo:** um link só entra no grafo e só pesa como critério importante de pesquisa quando estiver presente no corpo atual da nota src, no formato `[[Nome|uuid]]`, `[[Nome|f:uuid]]`, `[[Nome|c:uuid]]` ou `[[Nome|b:uuid]]`. Revisões antigas não contam; a referência operacional é sempre o conteúdo mais recente da nota src (`head_revision`/latest). Só `f:`, `b:` e `c:` têm semântica real de hierarquia; não inventar `h:` como role persistido.
2. **IA sem sequestrar o preview durante o processamento:** requests de IA devem viver como jobs assíncronos, com fila visível em balões flutuantes; o preview só pode ser ocupado quando existir resposta com conteúdo relevante para mostrar.
3. **Preservação estrutural de wikilinks pela IA:** a IA pode reescrever o texto visível do link, mas não pode remover nem corromper a estrutura `[[Titulo|uuid]]`, `[[Titulo|f:uuid]]`, `[[Titulo|c:uuid]]` ou `[[Titulo|b:uuid]]` existente.
4. **Toolbar mínima de IA:** a toolbar deve expor apenas três ações de IA: melhoria de marcação Markdown, revisão gramatical e tradução.
5. **Tradução com idioma e modelo independentes:** a ação de tradução deve permitir escolher separadamente língua alvo e modelo; deve criar/manter associação com a nota original, atualizar o título da nota traduzida e preservar/atualizar links relevantes.
6. **Promessa com geração por IA ao fechar `]]`:** ao concluir uma promessa e escolher gerar por IA, o backend já cria a nota vazia/preparada para receber o conteúdo, o editor insere o UUID correto no link, a requisição de IA segue de forma assíncrona e o usuário permanece na nota atual. Se reprovar a resposta, deve existir opção de desfazer, removendo a nota criada no banco e o link correspondente.
7. **Workflow de `/notes` com shell persistente:** a navegação entre notas deve preservar queue, estado de IA, finder e o máximo possível do estado do grafo/preview, atualizando apenas o conteúdo específico da nota. O objetivo não é migrar para React nem criar uma SPA paralela; a direção é usar a stack atual (Rails + Turbo + Stimulus + CodeMirror) para reduzir reloads completos.

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

**Direção arquitetural atual para navegação:**
- não reescrever a aplicação como SPA em React/Vue
- preservar a stack Rails + Turbo + Stimulus
- evoluir `/notes` para um **shell persistente** com troca parcial de conteúdo
- manter componentes globais montados uma vez só quando fizer sentido:
  - queue dock de IA
  - workspace/painel operacional de IA
  - note finder
  - casca estrutural do editor
- trocar apenas o contexto da nota atual:
  - conteúdo markdown
  - metadados da nota
  - backlinks
  - endpoints dependentes de `slug`
  - foco/painel do grafo embutido

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

### 3.1.1 Direção de Navegação e Persistência de Estado

Para a experiência de editor, o NeuraMD deve evitar reload completo da página ao trocar de nota.

**Objetivo:**
- fazer `/notes` se comportar como fluxo contínuo
- preservar estado de componentes operacionais
- reduzir remendos de restauração manual de estado após navegação

**Abordagem aprovada:**
- usar **shell persistente** com Rails + Turbo + Stimulus
- evitar criar frontend paralelo em React
- tratar a página da nota como:
  - **casca persistente**
  - **miolo trocável por nota**

**Estado que deve permanecer vivo entre trocas de nota quando possível:**
- queue dock da IA
- estado transitório da UI de IA que não depende exclusivamente do DOM da nota anterior
- note finder
- estado visual do app shell
- estado do grafo que puder ser preservado sem inconsistência

**Estado que pode ser reidratado a cada nota:**
- conteúdo do editor
- título/slug/idioma da nota atual
- URLs de autosave/checkpoint/IA dependentes do `slug`
- backlinks
- painel embutido do grafo focado na nota atual
- assinatura/realtime específica da nota atual

**Regra de implementação:**
- preferir navegação parcial em `/notes`
- evitar `window.location`/reload completo para trocar entre notas quando a navegação estiver dentro do fluxo do editor
- usar reload completo apenas quando a troca de contexto realmente exigir reinicialização integral da página

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
- modelo inicial: `qwen2.5:1.5b`

**Convenção atual do projeto para testes locais de IA:**

- `AI_PROVIDER=ollama`
- `AI_ENABLED_PROVIDERS=ollama`
- `OLLAMA_API_BASE=http://AIrch:11434`
- `OLLAMA_MODEL=qwen2.5:1.5b`

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
[[Display Text|uuid]]          → referência simples/legada
[[Display Text|f:uuid]]        → Father  — dst está ACIMA na hierarquia (target_is_parent)
[[Display Text|c:uuid]]        → Child   — dst está ABAIXO na hierarquia (target_is_child)
[[Display Text|b:uuid]]        → Brother — dst está no mesmo nível     (same_level)
```

**Separação de responsabilidades:**
- **Display Text** (antes do `|`) — texto livre escolhido pelo autor; pode ser alterado a qualquer momento sem quebrar o link; não precisa ser o título da nota destino
- **UUID** (depois do `|`) — referência imutável à nota destino; nunca muda mesmo se a nota for renomeada
- **Prefixo de role** (`f:`, `c:`, `b:`) — embutido antes do UUID; ausência = referência simples/legada

**Definição operacional de link ativo:**
- só é considerado **ativo** se estiver presente no conteúdo atual da nota src
- a fonte de verdade é a revisão mais recente da nota src (`head_revision`/latest), nunca revisões históricas
- links só contam como ativos se estiverem presentes no latest da nota src e apontarem para uma nota dst existente
- `f:`, `b:` e `c:` têm significado semântico no grafo
- outros prefixos não fazem parte do contrato operacional atual
- links legados ou históricos podem continuar renderizando, mas não devem pesar como aresta ativa do grafo fora das regras acima

**Fluxo de inserção:**
1. Usuário digita `[[`
2. Dropdown abre com sugestões filtradas pelo título da nota (busca em tempo real)
3. Usuário navega com `↓`/`↑`, seleciona com `Enter` ou `Tab`
4. Editor insere `[[Título da Nota|uuid]]` ou o formato com role explícito escolhido pelo fluxo, sem inventar `h:`
5. Após inserção, o usuário pode editar o Display Text livremente (o UUID permanece intacto)
6. Para definir hierarquia real, o usuário edita manualmente o prefixo para `|f:uuid`, `|c:uuid` ou `|b:uuid`

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
- `[[Display Text|f:uuid]]`, `[[Display Text|c:uuid]]`, `[[Display Text|b:uuid]]` → `<a href="/notes/slug" title="Título atual da nota">Display Text</a>` quando `dst` existir
- `[[Display Text|uuid]]` → renderiza por compatibilidade
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

### 4.6.1 Fila Visual de Requests Assíncronas

Toda request de IA relevante para o editor deve aparecer em uma fila visual flutuante, separando claramente:

- estado lógico da execução
- estado visual derivado para apresentação
- workspace de resposta útil no preview

**Modelo mínimo por item da fila:**

```ts
interface QueueItem {
  id: string;
  serviceType: "review" | "markdown" | "translation" | "creation";
  noteTitle: string;
  modelName: string | null;
  status: "queued" | "processing" | "success" | "error" | "cancelled";
  queuePosition: number;
  canCancel: boolean;
  canRetry: boolean;
}
```

**Regras de apresentação:**

- cada balão mostra exatamente três linhas: serviço, título da nota e modelo usado
- o balão deve ser compacto, flutuante e sem largura fixa rígida
- o título da nota não quebra linha; se necessário usa ellipsis
- o botão vermelho de cancelar fica no canto superior direito quando aplicável
- o rótulo curto do serviço deve ser derivado de `serviceType + status` por função centralizada

**Mapa visual por estado:**

- `queued`: borda cinza, pode arrastar, pode cancelar
- `processing`: borda amarela, pode cancelar, sem takeover do preview
- `success`: borda verde, sem cancelar, fora da priorização da fila ativa
- `error`: borda vermelha, clique no balão dispara retry consistente
- `cancelled`: sai da fila ativa sem reaparecer por atualização tardia

**Mecânica da fila:**

- a fila é vertical
- a frente da fila fica embaixo; itens menos prioritários ficam acima
- o container da fila tem scroll vertical próprio ao exceder a altura disponível
- deve existir reordenação manual por drag and drop para itens ainda ativos na fila
- durante o drag, o item original não pode continuar visível na posição antiga; usar placeholder real, não duplicata
- mudanças de estado não podem causar flicker, recriação agressiva do card ou reflow brusco

**Regras operacionais:**

- cancelar item `queued` remove da fila imediatamente
- cancelar item `processing` deve solicitar abort e blindar a UI contra resposta tardia
- retry de item `error` reenfileira como `queued` em posição coerente entre itens ainda ativos
- identidade visual e lógica devem usar `id` estável, nunca índice do array
- o preview só pode trocar para modo de revisão quando houver resposta útil; enquanto isso, só a fila visual representa progresso

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

- O estado atual de `/graph` e `/api/graph` é descartável se divergir deste plano
- Backend do grafo em Rails; frontend em JavaScript no browser integrado à página Rails, sem SPA paralela
- Stack da feature: Sigma.js, Graphology, `graphology-layout`, `graphology-layout-forceatlas2`, `graphology-layout-noverlap`, `graphology-traversal`

### 6.1 Estrutura e contrato

- `GET /graph` renderiza a página HTML do grafo
- `GET /api/graph` existe apenas como endpoint de dados do novo grafo
- o endpoint deve retornar dataset normalizado, nunca SVG pronto nem payload moldado pela UI antiga

```json
{
  "notes": [],
  "links": [],
  "tags": [],
  "noteTags": [],
  "linkTags": [],
  "meta": {
    "generated_at": "2026-03-15T12:00:00Z",
    "note_count": 0,
    "link_count": 0,
    "tag_count": 0
  }
}
```

**Regras do payload:**

- `notes` carregam `id`, `slug`, `title`, `excerpt`, datas básicas
- `links` carregam `id`, `src_note_id`, `dst_note_id`, `hier_role`, `context`
- `tags`, `noteTags` e `linkTags` bastam para o cliente montar índices auxiliares
- não enviar `content_markdown` completo no bootstrap do grafo
- `excerpt` deve ser curto e derivado de conteúdo indexável
- inconsistências podem ser omitidas do payload, mas devem ser logadas no backend

### 6.2 Construção do cliente do grafo

- cada `NoteDTO` vira um nó
- cada `NoteLinkDTO` vira uma aresta dirigida `src_note_id -> dst_note_id`
- a key da aresta é o próprio `note_link.id`
- arestas com `source` ou `target` inexistente devem ser ignoradas e logadas
- o cliente deve impedir duplicação estrutural de arestas ao montar o grafo

**Índices auxiliares obrigatórios:**

- `tagsByNoteId`
- `tagsByLinkId`
- `tagMetaById`
- `outEdgesByNodeId`
- `inEdgesByNodeId`
- `neighborDepth1Cache`
- `neighborDepth2Cache`

Esses índices só devem ser recalculados quando entrar dataset novo ou houver mutação estrutural real, nunca em hover.

### 6.3 Semântica visual

**Links:**

- `target_is_parent`: seta do lado do `target`
- `target_is_child`: seta do lado do `source`
- `same_level`: linha sem seta
- `null`: linha sem seta
- manter gap assimétrico entre extremidades para reforçar `src` e `dst`
- considerar como parâmetros iniciais: `srcPadding = 4`, `dstPadding = 10`
- como Sigma padrão não cobre bem seta seletiva e gap assimétrico, prever renderer customizado desde o início

**Nós:**

- `normal`: visível com cor plena
- `ghost`: contexto residual dessaturado, sem destaque de label por padrão
- `hidden`: sai da renderização

### 6.4 Filtros, foco e navegação

- filtros por `hier_role`, tags, profundidade e modo visual `all` vs `focused-tags`
- a cor efetiva de nó/aresta deve vir da primeira tag relevante dentro de `activeTagsOrdered.slice(0, topN)`
- clique em nó define `focusedNodeId`
- hover abre tooltip transitório
- clique fixa tooltip persistente; clicar em outro nó transfere o foco
- clique fora limpa foco e tooltip persistente
- tooltip deve ser HTML overlay, nunca desenhado dentro do canvas WebGL
- tooltip usa `title`, `excerpt` e CTA de navegação para a nota

**Organização local ao focar um nó:**

- `father` tende para cima
- `brother` tende para o meio
- `child` tende para baixo
- `src` tende para a esquerda e `dst` para a direita
- profundidade 2 preserva essa leitura com distância um pouco maior do foco

### 6.5 Sidebar, performance e aceite

**Sidebar mínima:**

- ordem manual de tags
- corte `Top-N`
- modo `all` vs `focused-tags`
- filtros por `hier_role`
- seleção de profundidade
- reset de foco

**Performance:**

- dataset com eager loading e serialização previsível
- nenhum N+1 no bootstrap
- payload inicial leve o suficiente para uso interativo
- layout e índices recalculados apenas quando necessário
- crescimento futuro aceitável via subgrafo, carregamento incremental ou cache serializado, sem quebrar o contrato

**Critérios de aceite:**

- `/graph` não depende da implementação anterior
- `/api/graph` segue o contrato normalizado acima
- foco por nó, profundidade e filtros por tags funcionam juntos
- semântica visual de `hier_role` é respeitada
- tooltip é HTML, persistente no clique e transitório no hover
- navegação para a nota funciona a partir do nó e do tooltip
- a UI continua integrada ao Rails

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
- **Wiki-links `[[Título|uuid]]`, `[[Título|f:uuid]]`, `[[Título|c:uuid]]`, `[[Título|b:uuid]]`** — autocomplete ao digitar `[[`, navegação com setas, inserção com Enter/Tab, link quebrado = fundo vermelho
- **Sincronização de links em checkpoints** — `Links::SyncService` extrai wiki-links do markdown atual e atualiza `note_links` (create/delete, sem duplicatas por `(src, dst, hier_role)`), considerando como ativos apenas os links presentes no latest
- **Backlinks no preview** — rodapé com lista de notas que linkam para esta nota
- Preview HTML via marked.js client-side (instantâneo, sem request)
- Botão "Gerar Áudio" → abre dialog TTS com idioma/provider/voz
- Player de áudio embutido quando `note_tts_asset` existe
- Suporte IME para input CJK (Mandarim/Japonês/Coreano)
- **Toolbar de IA mínima** — apenas: melhorar Markdown, revisão gramatical e tradução
- **Fila visual de IA** — jobs em processamento aparecem como balões flutuantes; preview só troca para workspace de resposta quando houver conteúdo relevante

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
    graph/
      dataset_builder.rb
      note_serializer.rb
      link_serializer.rb
      tag_serializer.rb
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
    graph/
      app_state.js
      graph_builder.js
      graph_indexes.js
      graph_filters.js
      graph_focus.js
      graph_layout.js
      graph_style.js
      graph_tags.js
      graph_tooltip.js
      graph_sidebar.js
      graph_custom_edge_program.js
  controllers/
    graphs_controller.rb
    api/
      graphs_controller.rb
  views/
    graphs/
      show.html.erb
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

### 11.1 Ordem de Implementação Técnica das Prioridades Atuais

Executar nesta ordem, porque cada etapa reduz ambiguidade da próxima e evita retrabalho entre editor, backend e UX de IA:

#### Etapa A — Normalizar o contrato de links ativos
- [x] Definir o contrato de links ativos usando apenas `|uuid`, `|f:uuid`, `|c:uuid` e `|b:uuid`, sem introduzir `h:` como role persistido
- [x] Ajustar parser/extractor para reconhecer apenas `f:`, `c:`, `b:` além de `|uuid`
- [x] Ajustar `Links::SyncService` para considerar apenas o conteúdo latest da nota src como fonte de verdade
- [x] Ajustar busca/grafo para dar peso apenas a links ativos no latest, com semântica real apenas para `f:`, `b:` e `c:`
- [x] Cobrir com specs de service/request para active links, links legados e remoção ao sair do latest

#### Etapa B — Fechar o fluxo de promessa com IA no backend
- [x] Ao escolher "gerar com IA", criar imediatamente a nota destino no backend, ainda vazia ou em estado preparado para hidratação assíncrona
- [x] Inserir no editor atual o wiki-link já resolvido com UUID real
- [x] Não navegar para a nota criada; a criação é backend-only nesse momento
- [x] Criar `ai_request` associado à nota recém-criada e colocá-lo na fila visual
- [x] Expor ação de desfazer/rejeitar que remove a nota criada no banco quando a resposta da IA não for aprovada
- [x] Cobrir com specs de request/system para criação sem navegação, enqueue assíncrono, undo e limpeza de banco
- [x] Validar o fluxo crítico em Playwright com duas promises consecutivas, cobrindo `queued -> running -> succeeded`, ordem serial de processamento e atualização visível da queue no shell

#### Etapa C — Reestruturar a UX operacional da IA
- [x] Separar estado de processamento do estado de resposta útil
- [x] Durante processamento, mostrar apenas balões flutuantes/queue cards, sem ocupar o preview
- [x] Permitir múltiplas requests simultâneas e cancelamento individual
- [x] Estruturar cada card da fila com três linhas: serviço, título da nota e modelo
- [x] Garantir fila vertical com frente da fila embaixo e scroll próprio no container
- [x] Implementar drag and drop com placeholder verdadeiro, sem duplicação visual do item arrastado
- [x] Mapear cor de borda por estado (`queued`, `processing`, `success`, `error`) e centralizar label curto por `serviceType + status`
- [x] Implementar blindagem explícita contra respostas tardias após cancelamento
- [x] Implementar retry de erro por clique no balão
- [x] Só abrir workspace de resposta quando existir conteúdo relevante para revisão/aplicação
- [x] Cobrir com specs de system para fila, cancelamento, polling e ausência de takeover do preview
- [x] Tratar Playwright como validação obrigatória dos fluxos de queue que dependem de editor, autosave, shell persistente e atualização visual em tempo real

#### Etapa C.5 — Transformar `/notes` em shell persistente
- [x] Extrair a casca estrutural do editor para permanecer montada entre trocas de nota
- [x] Tirar queue dock, workspace operacional de IA e note finder do fragmento específico da nota
- [x] Definir um contrato de carregamento parcial para `/notes/:slug` que permita trocar só o conteúdo dependente da nota atual
- [x] Interceptar navegação interna entre notas no workflow do editor para evitar reload completo
- [x] Atualizar URL e histórico sem desmontar o shell do editor
- [x] Reidratar apenas estado dependente da nota:
  - editor markdown
  - metadados (`title`, `slug`, `language`)
  - endpoints de autosave/checkpoint/IA
  - backlinks
  - painel embutido do grafo focado na nota atual
- [x] Preservar entre notas, sempre que consistente:
  - queue de IA global ao shell
  - workspace operacional de IA
  - note finder
  - estado visual do shell
- [x] Subir parte do histórico de IA para o shell global:
  - atividade recente de requests fora da nota atual
  - filtro explícito de shell no diálogo de histórico
- [x] Cobrir com specs de system para navegação entre notas sem reload integral da página e sem perda da queue
- [x] Expandir a cobertura para transições adicionais do workflow do editor:
  - note finder
  - backlinks
  - grafo embutido
  - histórico back/forward em sequências mais longas
- [x] Manter o grafo embutido persistente com foco barato por nota, evitando relayout quando só o nó focado muda
- [x] Refinar o histórico global do shell para decidir quanto sobe além da atividade recente:
  - manter atividade recente de requests no shell
  - manter também resultados aplicáveis e resultados reabertos

#### Etapa D — Endurecer preservação estrutural de wikilinks
- [x] Incluir nos prompts instruções explícitas para preservar a estrutura `[[texto|uuid]]`, `[[texto|f:uuid]]`, `[[texto|c:uuid]]` e `[[texto|b:uuid]]`
- [x] Implementar validação/pós-processamento para rejeitar ou corrigir respostas que corrompam wikilinks
- [x] Garantir que a IA possa alterar texto visível, mas nunca destruir o UUID nem os prefixos `f:`, `c:` e `b:` quando existirem
- [x] Cobrir com specs de service e system para revisão, melhoria de Markdown e tradução

#### Etapa E — Reduzir e estabilizar a toolbar de IA
- [x] Limitar a toolbar a três ações: melhorar Markdown, revisão gramatical e tradução
- [x] Remover ou esconder entradas redundantes de sugestão/rewrite fora desse recorte
- [x] Garantir que cada ação abra o fluxo correto sem conflitar com a fila de jobs
- [x] Cobrir com system specs da toolbar mínima

#### Etapa F — Concluir tradução assistida com nota associada
- [x] Implementar UI com escolha independente de língua alvo e modelo
- [x] Criar/atualizar nota traduzida associada à original
- [x] Atualizar título da nota traduzida conforme a língua alvo
- [x] Inserir no conteúdo traduzido a associação `Traduzida de [[Titulo original|b:uuid]]`
- [x] Ajustar links relevantes da nota traduzida preservando UUIDs e sem quebrar a relação com a original
- [x] Não criar backlink sintético na nota original nem `brother` recíproco sem que o link exista no corpo latest da nota dst
- [x] Cobrir com specs de request/service/system para criação, associação e preservação estrutural

#### Etapa G — Reconciliar grafo, busca e operações de descarte
- [x] Garantir que notas criadas por promessa com IA só entrem no grafo conforme seu latest válido
- [x] Garantir que o desfazer da promessa com IA remova nota, link e requests associados de forma consistente
- [x] Revisar impactos em pesquisa, backlinks e filtros do grafo
- [x] Rodar suíte de regressão focada em links, IA e tradução

**Critério de sequência:** não avançar para a etapa seguinte sem ter teste reproduzindo o comportamento e sem validar que a etapa anterior não reabriu regressão em links, preview ou fila de IA.

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
- [x] Ajustar o contrato prioritário de link ativo para `[[Título|uuid]]`, `[[Título|f:uuid]]`, `[[Título|c:uuid]]` e `[[Título|b:uuid]]`, sem introduzir `h:`
- [x] `Links::ExtractService` — extrair `f:`, `c:` e `b:` preservando semântica e compatibilidade com `|uuid`
- [x] `Links::SyncService` — considerar apenas links presentes no latest da nota src como ativos no grafo; revisões antigas não contam
- [x] ~~`Links::TitleSyncService`~~ — não necessário; Display Text é livre e não rastreia o título da nota
- [x] CodeMirror extension: detecta `[[`, abre dropdown Stimulus com sugestões via fetch, navega com `↑`/`↓`, insere com `Enter`/`Tab`, fecha com `Esc`
- [x] Decoração de link quebrado: UUID não encontrado no DB → classe CSS `wikilink-broken` (fundo vermelho) no editor via CodeMirror ViewPlugin
- [x] Preview: render `[[Título|uuid]]` como `<a href="/notes/slug">Título</a>` (client-side no preview controller)
- [x] Preview: se UUID inexistente, render como `<span class="wikilink-broken">Título</span>`
- [x] Backlinks no preview: seção no rodapé com notas src linkando para a nota atual
- [x] Fluxo de promessa: ao fechar `]]` e escolher IA, criar a nota no backend, inserir UUID correto no link atual, enfileirar job visual e permanecer na nota atual
- [x] Desfazer promessa com IA rejeitada: apagar a nota criada no banco e remover o link quando o usuário descartar a resposta
- [x] Specs: ExtractService, SyncService, endpoint search, render com links ativos/legados e promessa com IA

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
- [x] Revisar a feature do grafo partindo do contrato consolidado neste `PLAN.md`, sem reaproveitar por inércia a implementação atual
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

#### Fase 5 — Prioridades de UX e preservação estrutural

- [x] Remover overlay/modal bloqueante durante processamento; usar apenas balões flutuantes e fila de jobs enquanto não houver resposta útil
- [x] Permitir múltiplas requisições enfileiradas e cancelamento individual
- [x] Cada item da fila deve ser um balão compacto com serviço, título da nota e modelo usado
- [x] A fila deve ser vertical, com frente embaixo, scroll próprio e reordenação por drag and drop
- [x] Durante drag, usar placeholder e impedir duplicata visível do mesmo item
- [x] Borda por estado: cinza (`queued`), amarela (`processing`), verde (`success`), vermelha (`error`)
- [x] Retry por clique em item com erro; cancelamento imediato para itens ainda ativos
- [x] Separar claramente estado lógico (`queued/running/succeeded/failed/cancelled`) do estado visual derivado
- [x] O preview só pode ser substituído quando existir resposta com conteúdo relevante
- [x] Reduzir toolbar de IA para exatamente três ações: melhorar Markdown, revisão gramatical e tradução
- [x] Endurecer prompts e pós-processamento para preservar wikilinks existentes (`[[Titulo|uuid]]`, `[[Titulo|f:uuid]]`, `[[Titulo|c:uuid]]`, `[[Titulo|b:uuid]]`)
- [x] Validar resposta de IA antes de aplicar: nunca quebrar/remover a parte estrutural `[[...|uuid]]` e seus prefixos hierárquicos válidos
- [x] Para promessa com IA, manter criação backend-only até aprovação; se houver descarte, remover a nota criada
- [x] Specs de system/request para fila visual, cancelamento e preservação estrutural de wikilinks

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
  - `SeedNoteOutputGuard` — rejeita output vazio, prompt echo, markers proibidos
  - `WikilinkOutputGuard` — restaura payloads missing, sanitiza payloads inválidos
- `spec/system/ai_review_spec.rb`
  - abrir modal pelo toolbar
  - processar seleção
  - processar documento inteiro
  - aplicar texto no CodeMirror
  - exibir fallback de “IA não configurada”
- `spec/jobs/ai/review_job_spec.rb`
  - enfileirar requisições para `AIrch` (queue: `:airch`)
  - persistir estado `queued/running/succeeded/failed`
  - reprocessar falhas transitórias de rede
- `spec/system/wikilink_editor_spec.rb` (24 specs)
  - autocomplete dropdown (abrir, filtrar, navegar, inserir, scroll, cosine similarity)
  - promessa: criar nota em branco, gerar com IA, ignorar
  - tag sidebar: link mode vs global mode por posição do cursor
- `spec/services/notes/promise_*_spec.rb`
  - `PromiseFulfillmentService` — aplica output, rejeita output vazio, não sobrescreve conteúdo
  - `PromiseCleanupService` — soft-delete nota, reverte wikilink, cancela request

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
- [x] Nova capability `translate`
- [x] UI de tradução com duas escolhas independentes: língua alvo e modelo
- [x] Criar nota irmã (`brother`) a partir de uma nota existente para armazenar a tradução
- [x] Vincular idioma de origem/destino na nota e na request
- [x] Atualizar o título da nota traduzida para refletir a língua alvo
- [x] Inserir no corpo traduzido a associação explícita com a nota original: `Traduzida de [[Titulo original|b:uuid]]`
- [x] Atualizar links necessários da nota traduzida para manter associação com a nota original sem quebrar UUIDs
- [x] Não criar dois links `brother` sintéticos; só pode existir link persistido quando a nota src realmente tiver o markup correspondente no corpo latest
- [x] Corrigir o bug atual em que a tradução cria link recíproco para uma nota dst que não contém o link em seu próprio corpo
- [x] Fluxo inicial priorizando `pt-BR -> en`
- [ ] Benchmarks adicionais com textos maiores e Markdown real
- **Entrega:** tradução controlada, auditável e sem misturar idiomas na mesma nota

### Fase 6 — TTS com Cache (ElevenLabs + Fish Audio + Gemini + Kokoro)
- [x] `Tts::BaseProvider` interface + `ElevenlabsProvider` + `FishAudioProvider` + `GeminiProvider` + `KokoroProvider`
- [x] `note_tts_assets` com cache por SHA256 hash do texto + provider + voice
- [x] Detecção automática de idioma da nota (`detected_language`)
- [x] UI: dialog "Gerar Áudio" com 2 abas (Gerar + Biblioteca), provider/voz/idioma/formato selects
- [x] Player embutido na nota com speed control (0.75x/1x/1.25x/1.5x), info bar, karaoke toggle
- [x] Fluxo de rejeição: "Rejeitar" desativa asset, "Gerar" com novas configurações
- [x] Suporte a zh-CN, zh-TW, ja-JP, ko-KR (Kokoro + Gemini)
- [x] Definir bind mounts de workspace para Kokoro e MFA usando `SHARED_AI_ROOT`
- [x] Padronizar nomeação de artefatos compartilhados por `note_revision_id`
- [x] TTS cards no AI History com badges (provider/voz/idioma) e mini audio player
- [x] Audio Library: `GET /notes/:slug/tts_library` → lista todos assets da nota
- [x] MFA alignment pipeline: `Mfa::AlignService` → SSH to AIrch → `docker exec mfa mfa align` → JSONB
- [x] Karaoke player: `karaoke_controller.js` com binary search em `timeupdate`, click-to-seek
- [x] Auto-checkpoint antes de gerar TTS (revisão sempre vinculada a um marco)
- [x] Stale audio notice quando nota é editada após TTS, com opção de carregar áudio da revisão anterior
- [x] Queue cards de TTS auto-resolvem quando processamento conclui
- [x] Strip de markdown/wikilinks do texto antes de enviar ao provider TTS
- [x] Fila única `airch` (1 thread) para processamento sequencial AI/TTS/MFA no AIrch
- [x] System specs E2E: dialog, karaoke, stale notice, library (8 specs, Capybara+Cuprite)
- [x] Fix karaoke span injection: guard contra Stimulus double-fire + MutationObserver para re-render do preview
- [x] Strip de parênteses/colchetes do texto TTS para compatibilidade MFA
- [x] Conversão de quebras de linha em pausas (`. `) para TTS natural em headings/parágrafos
- [x] Remapeamento de palavras compostas no MFA: merge "bem"+"estar" → "bem-estar" com timing expandido
- [x] Agrupamento de palavras curtas no karaoke: 2 passes (consecutivas + merge com vizinha) para garantir ≥200ms de visibilidade por grupo
- **Entrega:** áudio eficiente e multi-idioma com karaoke sincronizado

#### Fase 6 — Gotchas e decisões de implementação

- Zeitwerk: `ElevenlabsProvider` (não `ElevenLabsProvider`) — `elevenlabs_provider.rb` mapeia para `Elevenlabs`
- `Tts::Error` e `Mfa::Error` + subclasses em `error.rb` — carregados via `require_relative`, não autoload individual do Zeitwerk
- `Ai::InvalidOutputError` em `ai/error.rb` — precisa de `require_relative "error"` em qualquer service que o use diretamente (ex: `seed_note_output_guard.rb`)
- Gemini TTS retorna áudio base64 em JSON (não binário) — usa `post_json`, não `post_binary`
- `format` como parâmetro HTTP conflita com Rails (interpreta como formato de resposta) — renomeado para `audio_format` em JS e Ruby
- Validação `voice: presence: true` — service deve defaultar para primeira voz disponível quando vazio
- Stimulus `alignmentValueChanged()` callback: só dispara ao usar setter da API (`controller.alignmentValue = data`), NOT `dataset.karaokeAlignmentValue = JSON.stringify(data)`
- Queue cards de TTS: auto-resolver via `_resolveQueueRequest()` no handler de stream quando `capability === "tts" && status === "succeeded"`
- `Note.search_by_title` usa scope `with_latest_content` que exige `head_revision_id` — notas sem revisão checkpoint não aparecem em autocomplete/search
- Backlinks panel é `hidden` por default (footer mostra Grafo) — testes que verificam backlinks devem trocar para "Backlinks" primeiro
- MFA `RemoteExecutor` precisa de timeout de execução (`Timeout.timeout(300)`) além do connect timeout SSH, para evitar travar a fila inteira
- Fila `airch` (1 thread, 1 process) garante processamento sequencial no AIrch — AI, TTS e MFA compartilham a mesma fila
- `config/brakeman.ignore` contém false positive para `Open3.capture3` no `RemoteExecutor` (array-based, sem shell, valores de ENV internos)
- MFA roda nativo via mamba (não Docker): `~/.local/share/mamba/envs/mfa/bin/mfa` — mais estável e rápido que `docker exec`
- Karaoke word grouping: palavras <200ms são agrupadas em 2 passes — (1) consecutivas curtas juntas, (2) grupos ainda <200ms absorvidos pelo vizinho mais próximo
- Karaoke CSS: `.karaoke-active` fora de `@layer components` para máxima especificidade em Tailwind v4
- `innerText` do preview como fonte de texto TTS — já vem sem markdown, preserva quebras de linha entre blocos

#### Fase 6 — Testes Paralelos com AIrch

O host `AIrch` (rafael@AIrch.local) pode executar a bateria de testes em paralelo com a máquina de desenvolvimento, dividindo a carga de CPU. Setup:

**Infraestrutura no AIrch:**
- Ruby 3.3.10 via mise (mesmo que dev)
- PostgreSQL 17 (user `rafael`, database `neuramd_test`)
- Chromium headless para system specs (Capybara+Cuprite)
- Código sincronizado via rsync

**Script `bin/rspec-airch`:**
```bash
bin/rspec-airch [--sync] [spec paths...]
```
- `--sync` executa rsync antes de rodar (código + Gemfile + migrations)
- Roda `bundle install`, `rails db:migrate`, então `rspec` via SSH
- Pode rodar subsets de specs no AIrch enquanto dev roda outros localmente

**Estratégia de divisão:**
- **AIrch:** specs unitários/request (rápidos, CPU-bound, sem browser): `spec/models/`, `spec/services/`, `spec/requests/`, `spec/jobs/`
- **Dev local:** system specs (browser-bound, Cuprite): `spec/system/`
- Exemplo: `bin/rspec-airch --sync spec/models/ spec/services/ spec/requests/` em paralelo com `bundle exec rspec spec/system/`

**Requisitos:**
- SSH sem senha configurado (`~/.ssh/authorized_keys`)
- NFS mount compartilhado em `/mnt/AIrch/data/` para artefatos MFA/TTS
- `DATABASE_URL` configurado no AIrch para PostgreSQL local

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

**Serviços ativos no AIrch:**

- Kokoro TTS: FastAPI server nativo em `~/kokoro-env/kokoro_server.py`, systemd user service na porta 8880
- Montreal Forced Aligner: instalação nativa via mamba em `~/.local/share/mamba/envs/mfa/bin/mfa` (não usa Docker — mais rápido e estável)
- NFS paths: local `/mnt/AIrch/data/mfa/{input,output}` ↔ remoto `/srv/airch-data/mfa/{input,output}`
- Alignments permanentes: `/mnt/AIrch/data/alignments/json/`

### Fase 7 — Polimento Editor e UX (forte inspiracao FrankMD)

> **Referencia:** `~/projects/FrankMD` — portar controles, dialogs e padroes visuais.
> **Principio:** o editor NeuraMD deve ter a mesma fluencia do FrankMD, preservando as features exclusivas (wiki-links, grafo, TTS, MFA).

#### 7.0 — Correcoes de Layout (PRIORIDADE)

**Scroll do editor:**
- [x] Bug: texto cabe no editor mas scroll desloca para baixo escondendo conteudo
- [x] Investigar padding/margin do `.cm-content` e `#codemirror-host` que gera scroll desnecessario
- [ ] Typewriter mode (40vh padding) nao deve aplicar quando desativado — verificar residual

**Footer (Grafo/Backlinks) independente do scroll do preview:**
- [x] Extrair `.note-context-panel` para FORA do `#preview-pane` overflow container
- [x] Layout: preview-pane vira flex column com `flex: 1 1 auto; overflow-y: auto` para o conteudo e `flex: 0 0 auto` para o footer
- [x] Footer ocupa sua propria regiao visual — scroll do preview NAO afeta grafo/backlinks
- [x] Resize handle continua funcional entre preview e footer

**Graph resize bug:**
- [x] Bug atual: ao redimensionar o grafo, se scroll esconde parte dele, o Sigma.js da zoom ao inves de ocupar area visivel
- [x] Fix: forcar `sigma.refresh()` / resize apos mutation do container (ResizeObserver)
- [x] Graph canvas deve preencher 100% do container visivel, sem depender de scroll
- [x] Testar com ResizeObserver no `graph_controller.js` para recalcular dimensoes ao redimensionar

**Workspace de diff/translation da IA:**
- [x] Corrigir scroll interno do diff/proposta no workspace de IA para textos longos, inclusive no fluxo de traducao

#### 7.1 — Toolbar Revisada

**Limpar toolbar atual:**
- [ ] Remover label "auto" do badge de idioma — so mostrar quando ha idioma detectado (ex: "pt-BR", "en")
- [ ] Remover indicadores poluentes que nao comunicam acao clara
- [ ] Padronizar visual de TODOS os botoes: mesma altura, padding, hover, active state
- [ ] Agrupar por funcao com separadores visuais:
  - Grupo 1: Navegacao (voltar ao grafo)
  - Grupo 2: Titulo + idioma + tags
  - Grupo 3: Formatacao (bold, italic, code, link, strikethrough, highlight, heading, lista, quote, code block)
  - Grupo 4: Inserir (tabela, emoji, imagem, video embed)
  - Grupo 5: IA (rewrite, grammar, translate)
  - Grupo 6: TTS (gerar, status)
  - Grupo 7: Editor (preview toggle, typewriter, find/replace)
  - Grupo 8: Save (status, revisoes, checkpoint)

**Novos botoes da toolbar (portar do FrankMD):**
- [ ] Strikethrough (`~~texto~~`) — `Ctrl+Shift+S`
- [ ] Highlight (`==texto==`) — `Ctrl+Shift+H`
- [ ] Headings H1/H2/H3 — dropdown ou botoes individuais
- [ ] Bullet list (`- `) / Numbered list (`1. `) / Blockquote (`> `)
- [ ] Code block (``` ```) — `Ctrl+Shift+C`
- [ ] Tabela — abre Table Editor dialog
- [ ] Emoji picker — abre Emoji dialog
- [ ] Imagem — upload/insert via Active Storage

**Acoes que nao funcionam (auditar e implementar ou remover):**
- [ ] Auditar cada botao da toolbar atual — listar os que nao respondem
- [ ] Implementar ou remover botoes mortos — zero botoes decorativos

#### 7.2 — Table Editor (portar do FrankMD)

- [ ] Dialog modal com grid visual para criar/editar tabelas Markdown
- [ ] Inputs por celula, header row com estilo diferenciado
- [ ] Operacoes: add/remove/mover colunas e linhas
- [ ] Menu de contexto por celula (right-click)
- [ ] Detectar tabela existente sob cursor e abrir em modo edicao
- [ ] Gerar markdown formatado com pipes e separadores
- [ ] Portar `table_editor_controller.js` e `table_utils.js` do FrankMD
- [ ] Adaptar para inserir no CodeMirror via API do NeuraMD (dispatch `codemirror:insert`)

#### 7.3 — Emoji Picker (portar do FrankMD)

- [ ] Dialog com 2 abas: Unicode emojis + Kaomoji emoticons
- [ ] Busca por shortcode (`:smile:`) e keywords em ingles
- [ ] Grid navegavel por teclado (setas, Page Up/Down)
- [ ] Preview panel com nome/shortcode do item selecionado
- [ ] 150+ kaomoji organizados por categoria (Happy, Love, Sad, Actions, etc.)
- [ ] `Ctrl+Shift+E` para abrir picker
- [ ] Portar `emoji_picker_controller.js`, `emoji_data.js`, `emoji_i18n.js` do FrankMD

**Integracao com TTS:**
- [ ] Emoji/emoticon inserido como Unicode — Kokoro/MFA tratam como caractere normal
- [ ] `strip_markup` em `GenerateService` deve remover emojis Unicode antes de enviar ao TTS
- [ ] Regex: `text.gsub(/[\u{1F600}-\u{1F64F}\u{1F300}-\u{1F5FF}\u{1F680}-\u{1F6FF}\u{1F1E0}-\u{1F1FF}\u{2600}-\u{26FF}\u{2700}-\u{27BF}]/, "")`
- [ ] Kaomoji: ja sao caracteres texto — MFA pode ou nao alinhar; testar e decidir se strip

#### 7.4 — Themes (portar do FrankMD)

- [ ] System de themes via CSS custom properties (`--theme-bg-primary`, `--theme-text-primary`, `--theme-accent`, etc.)
- [ ] `data-theme="theme-id"` no `<html>` + classe `dark` para Tailwind
- [ ] Picker dropdown na toolbar (ou dialog de customizacao)
- [ ] Persistencia: `localStorage` + config no backend
- [ ] Dark mode auto-detection via `prefers-color-scheme`
- [ ] Portar subset inicial de themes do FrankMD:
  - Dark (default)
  - Light
  - Nord
  - Tokyo Night
  - Catppuccin
  - Gruvbox
  - Solarized Dark/Light
  - Rose Pine
- [ ] Adaptar CSS do NeuraMD para usar custom properties (substituir cores hardcoded)
- [ ] CodeMirror theme deve reagir a mudanca de theme (reconfigurar highlighting)
- [ ] Preview, grafo, sidebar, toolbar — todos devem respeitar o theme ativo

#### 7.5 — Font Dialog e Customizacao (portar do FrankMD)

- [ ] Dialog de customizacao: font family + font size + preview ao vivo
- [ ] Fonts monospacadas disponiveis (portar do FrankMD):
  - Cascadia Code, Fira Code, JetBrains Mono, Hack, Consolas, DejaVu Sans Mono, Roboto Mono, Source Code Pro, Ubuntu Mono
- [ ] Tamanhos: 12px a 24px
- [ ] CSS custom properties: `--editor-font-family`, `--editor-font-size`
- [ ] Preview zoom: 50% a 200% (9 niveis)
- [ ] Persistencia em localStorage
- [ ] Portar `customize_controller.js` do FrankMD

#### 7.6 — Typewriter Mode Melhorado

O typewriter mode atual no NeuraMD e superficial: apenas aplica `padding-top/bottom: 40vh` no `.cm-scroller`.
Isso nao reproduz o comportamento do FrankMD. O objetivo correto nao e "empurrar o texto para o meio", e sim
**manter a linha/cursor de escrita em uma faixa visual estavel, preferencialmente no centro da viewport**, com
sincronizacao coerente do preview e sem degradar a experiencia de selecao, links ou IME.

**Referencia tecnica principal no FrankMD:**
- `app/javascript/controllers/typewriter_controller.js`
- `app/javascript/lib/codemirror_typewriter.js`
- `app/javascript/lib/typewriter_utils.js`
- `app/javascript/controllers/preview_controller.js`
- `app/assets/tailwind/components/codemirror.css`
- `app/assets/tailwind/components/editor.css`

**Objetivo funcional do Typewriter Mode:**
- [ ] Cursor deve permanecer aproximadamente em 50% da area visivel do editor durante digitacao normal
- [x] Reduzir movimento ocular e scroll manual em sessoes longas de escrita
- [ ] Preservar fluidez de escrita com markdown, wikilinks, CJK/IME e selecao de texto
- [ ] Nao transformar o editor em preview falso; o documento continua sendo markdown editavel

**Arquitetura desejada herdada do FrankMD:**
- [x] `typewriter_controller.js` vira orquestrador de UI/estado, nao implementacao de scroll
- [x] Estado `enabled` deve ser persistido e refletido no botao (`aria-pressed`, classe ativa, shortcut)
- [x] CodeMirror recebe extensao dedicada `codemirror_typewriter.js`
- [ ] Extensao deve expor efeitos/estado equivalentes a:
  - `setTypewriterMode`
  - `setIsSelecting`
  - `typewriterState`
- [x] `codemirror_controller.js` deve fornecer API publica equivalente a:
  - `setTypewriterMode(enabled)`
  - `toggleTypewriterMode()`
  - `isTypewriterMode()`
  - `getTypewriterSyncData()`
  - `maintainTypewriterScroll()`
- [ ] `typewriter_utils.js` deve concentrar calculos puros e testaveis:
  - `calculateTypewriterScroll`
  - `getTypewriterSyncData`
  - `calculateTypewriterSyncRatio`

**Comportamento do editor:**
- [x] Ao ativar o modo, recentrar imediatamente o cursor atual
- [x] Em `selectionSet` ou `docChanged`, recentrar de novo quando houver apenas cursor simples
- [x] Durante drag-selection com mouse, desativar recentralizacao temporariamente para evitar jitter
- [ ] Enquanto existir selecao real (`anchor != head`), nao auto-scrollar
- [x] Usar `coordsAtPos` + `scrollDOM.clientHeight` para calcular o `scrollTop` alvo
- [x] Fazer clamp no intervalo valido do scroller
- [x] Usar `setTimeout(..., 0)` ou equivalente apenas para deixar o scroll ocorrer apos o proprio ajuste do CodeMirror, como no FrankMD
- [x] Nao depender de `40vh` hardcoded como implementacao principal

**Padding e layout visual:**
- [x] `padding-bottom` do scroller deve ser calculado dinamicamente a partir da altura visivel real do editor
- [x] Ao desativar o modo, limpar TODO padding inline residual
- [x] O container do editor deve cooperar com centragem horizontal, seguindo a direcao do FrankMD:
  - wrapper pode centralizar o corpo do editor
  - body/editor devem respeitar largura maxima coerente
  - `.cm-content` nao deve manter margens/paddings conflitantes
- [ ] O layout nao pode reintroduzir scroll fantasma nem conflito com stats bar/footer
- [x] Primeira camada de focus mode: ocultar chrome secundario e sobrepor preview a area principal de escrita
- [x] Primeira camada de limpeza do markdown cru: ocultar prefixos estruturais seguros (heading/lista/blockquote/code fence) no texto visivel do editor em typewriter

**Sincronizacao com preview:**
- [x] Preview deve receber estado explicito de typewriter mode
- [x] Preview deve acompanhar a linha atual do cursor em vez de apenas proporcao bruta de scroll
- [x] A sincronizacao deve considerar padding extra do modo typewriter no preview
- [x] Preview so deve animar quando a diferenca superar um threshold minimo para evitar jitter
- [x] Usar double `requestAnimationFrame` ou estrategia equivalente quando necessario para esperar layout/render

**Wikilinks no typewriter: exigencia especial do NeuraMD**
- [x] No typewriter mode, wikilinks `[[Titulo|uuid]]`, `[[Titulo|f:uuid]]`, `[[Titulo|c:uuid]]`, `[[Titulo|b:uuid]]` devem ser exibidos visualmente igual ao preview
- [ ] "Igual ao preview" significa:
  - [x] mostrar apenas o texto visivel do link
  - [x] aplicar a mesma semantica visual de links validos/quebrados
  - [x] respeitar `f:`, `c:` e `b:` na aparencia quando houver convencao visual correspondente
- [x] O markdown subjacente NAO pode ser alterado; `|uuid` e `|role:uuid` continuam existindo no documento real
- [x] A ocultacao de UUID/role deve ser feita por camada visual do CodeMirror:
  - decorations
  - widgets
  - replacement ranges
- [ ] Clique/hover/foco no wikilink em typewriter deve preservar editabilidade:
  - permitir navegar para a nota quando isso ja fizer parte do contrato do editor
  - [x] permitir revelar/editar a forma completa quando necessario
  - nunca corromper o UUID estrutural
- [x] Spans inline limpos pelo typewriter devem revelar a sintaxe ao receber foco/cursor local para edicao direta
- [ ] O comportamento visual do typewriter para wikilinks deve ser consistente com a regra global de preservacao estrutural de links
- [x] Links quebrados em typewriter devem ser distinguiveis visualmente, tal como no preview

**Regra de escopo para a primeira entrega:**
- [x] Primeira entrega aceita "renderizacao hibrida" apenas no typewriter mode
- [ ] Fora do typewriter, o editor pode continuar mostrando markdown cru temporariamente
- [ ] Nao implementar "preview falso completo" de markdown no editor; o foco inicial e wikilinks

**Interacao com IME e idiomas CJK:**
- [ ] Auto-scroll nao pode interferir com composicao de texto via IME
- [ ] Testar com Mandarim/Japones/Coreano, especialmente durante composicao inline
- [ ] Nao recentralizar agressivamente no meio de composicao ainda nao confirmada

**Persistencia e atalhos:**
- [x] Persistir estado em `localStorage` no minimo; opcionalmente espelhar em config backend depois
- [x] Manter atalho `Ctrl+\` coerente com help/toolbar
- [x] Estado do botao da toolbar deve refletir o estado real da extensao, nao apenas uma classe CSS

**Matriz minima de testes inspirada no FrankMD:**
- [ ] Unit tests para `typewriter_utils.js`
- [ ] Tests do controller Stimulus:
  - toggle liga/desliga corretamente
  - `aria-pressed` e classe ativa atualizam
  - delega para o `codemirror_controller`
- [ ] Tests da extensao CodeMirror:
  - adiciona/remove classe `typewriter-mode`
  - adiciona/remove padding dinamico
  - recentraliza ao mover cursor
  - nao recentraliza durante selecao com mouse
- [ ] Tests de preview sync em typewriter mode
- [ ] Tests de wikilink em typewriter:
  - `[[Titulo|uuid]]` exibe so o texto visivel
  - `[[Titulo|f:uuid]]` / `c:` / `b:` preservam semantica visual
  - [x] link quebrado aparece como quebrado
  - [x] `ArrowDown`/`ArrowUp` sobre link completo permite editar rapidamente o role sem corromper o UUID
  - sair do typewriter devolve exibicao crua do markdown, sem perda estrutural
- [ ] System/Playwright:
  - ativar typewriter e digitar em documento longo
  - cursor permanece aproximadamente centralizado
  - preview acompanha
  - wikilinks aparecem como no preview
  - desativar typewriter restaura layout e exibicao normal sem residual
- [x] System spec inicial no NeuraMD cobre exibicao visivel de wikilink em typewriter sem expor UUID no texto renderizado
- [x] System spec inicial cobre layout enxuto do typewriter (toolbar/sidebar ocultos e preview sobreposto)
- [x] System spec inicial cobre ocultacao de prefixos estruturais de heading/lista/blockquote/code fence no texto visivel do typewriter

#### 7.7 — Internacionalizacao (i18n)

- [ ] Implementar sistema de traducao client-side: `window.t(key)` helper global
- [ ] Locales iniciais: `pt-BR` (default), `en`, `es`
- [ ] Arquivos de traducao JSON carregados no frontend
- [ ] Picker de idioma na toolbar ou dialog de customizacao
- [ ] Persistencia: localStorage + config backend
- [ ] Traduzir: toolbar labels, dialogs, status messages, placeholders
- [ ] Portar `locale_controller.js` do FrankMD, adaptar para NeuraMD endpoints

#### 7.8 — AI Grammar Melhorada

A implementacao atual funciona mas pode ser mais fluida:

- [ ] **Diff visual word-level:** portar `diff_utils.js` do FrankMD para diff colorido palavra-por-palavra
  - Painel esquerdo: texto original com delecoes em vermelho
  - Painel direito: texto corrigido com adicoes em verde
- [ ] **Modo edicao no resultado:** toggle para editar o texto corrigido antes de aceitar
- [ ] **Grammarly extension:** documentar que CodeMirror 6 suporta Grammarly nativamente via contenteditable
  - Nenhuma integracao custom necessaria — Grammarly browser extension funciona se `contenteditable` ativo
  - Testar e documentar compatibilidade
- [ ] **Inline suggestions (futuro):** ao inves de dialog, mostrar sugestoes inline no editor com accept/reject

#### 7.9 — Imagens e Media

- [ ] Upload de imagem via Active Storage com drag-and-drop no editor
- [ ] Dialog de insercao de imagem (URL ou upload)
- [ ] Grid de imagens da nota (galeria)
- [ ] Embed YouTube: dialog com URL → gera markdown/HTML embed
- [ ] Preview renderiza embeds inline

#### 7.10 — Historico de Revisoes com Diff Visual

- [ ] UI para navegar revisoes (timeline ou lista)
- [ ] Diff visual entre revisoes (word-level ou line-level)
- [ ] Restaurar revisao anterior
- [ ] Reutilizar `diff_utils.js` do item 7.8

#### 7.11 — Keyboard Shortcuts Padronizados

Portar e padronizar do FrankMD:

| Shortcut | Acao |
|----------|------|
| `Ctrl+B` | Bold |
| `Ctrl+I` | Italic |
| `Ctrl+K` | Link |
| `` Ctrl+` `` | Inline code |
| `Ctrl+Shift+S` | Strikethrough |
| `Ctrl+Shift+H` | Highlight |
| `Ctrl+Shift+C` | Code block |
| `Ctrl+Shift+E` | Emoji picker |
| `Ctrl+Shift+A` | TTS dialog (Audio) |
| `Ctrl+P` | Toggle preview (ja existe) |
| `Ctrl+\` | Typewriter mode |
| `Ctrl+F` | Find in file |
| `Ctrl+H` | Find & Replace |
| `Ctrl+G` | Jump to line |
| `Ctrl+Shift+K` | Note finder (ja existe) |
| `F1` | Help / keyboard shortcuts reference |

- **Entrega:** editor com a fluencia e polimento do FrankMD, features exclusivas do NeuraMD preservadas

#### 7.12 — TTS UX Refinamentos

**Dialog "Criar Audio" como Dropdown padrao:**
- [ ] O dialog de TTS deve seguir o mesmo padrao visual de dropdown dos outros recursos (IA, tags, etc.)
- [ ] Consistencia de interacao: abrir, selecionar, fechar — sem modal pesado

**Aba Biblioteca — navegar para a revisao ao inves de reproduzir inline:**
- [ ] Ao clicar em um item da biblioteca, fechar o dialog e navegar para a revisao da nota associada ao audio
- [ ] A reproducao do audio acontece na pagina da revisao (player embutido), nao dentro do dialog
- [ ] Simplifica o dialog: biblioteca vira lista de links para revisoes, sem mini-players

**Karaoke click-to-seek sem sublinhado no preview:**
- [ ] Manter funcionalidade de clicar na palavra e pular para o segundo correto do audio
- [ ] Remover o sublinhado visual (underline/border-bottom) das palavras no preview durante karaoke
- [ ] Karaoke ativo deve usar apenas highlight de fundo (background), sem decoracao de texto adicional

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
| Grafo consolidado neste `PLAN.md` | Evitar drift entre visão de produto e implementação da feature |

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

**Política para fluxos críticos de IA no editor:** tudo que combinar editor real, promise creation, shell persistente, autosave, queue visual e transição assíncrona de status deve ser validado por Playwright antes de ser considerado concluído. Request/system specs continuam obrigatórias para contrato e regressão local, mas não substituem a prova E2E do fluxo no browser.

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

*Última atualização: 2026-03-21 (plano consolidado; grafo e queue absorvidos)*
*NeuraMD — Stack: Rails 8 · PostgreSQL 16 · Hotwire · CodeMirror 6 · Docker*
