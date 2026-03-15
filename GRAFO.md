# Especificação Técnica — Grafo de Notas no NeuraMD

## Status

Este documento substitui integralmente a implementação atual do grafo.

- O estado atual de `/graph` e `/api/graph` deve ser tratado como descartável.
- Não assumir compatibilidade com payloads, controllers, services ou UI existentes.
- O objetivo é atingir o resultado final descrito aqui, mesmo que isso exija recomeçar a feature.

---

## Objetivo

Construir uma experiência de exploração de grafo grande de notas, com foco em:

- renderização de muitos nós e links
- layout dinâmico e estável
- foco contextual por nó selecionado
- filtro e hierarquia visual por Tags
- tooltip persistente com navegação para a nota
- semântica visual específica para arestas
- arquitetura sem React
- integração natural com Rails, Hotwire e o modelo de dados do NeuraMD

---

## Diretriz de stack

### Backend

- Ruby on Rails
- PostgreSQL
- serialização do dataset em Ruby
- autenticação/autorização pelas regras normais da aplicação

### Frontend

- JavaScript ou TypeScript executado no browser
- Stimulus para bootstrap e integração com a página Rails
- Sigma.js para renderização
- Graphology para estrutura e algoritmos do grafo
- `graphology-layout`
- `graphology-layout-forceatlas2`
- `graphology-layout-noverlap`
- `graphology-traversal`

### Fora de escopo como exigência

- Node.js como backend
- Vite como pré-requisito arquitetural
- criação de uma SPA separada do Rails

Observação:
- Se em algum momento houver bundling JS moderno no projeto, isso é detalhe de implementação.
- A feature do grafo não depende conceitualmente de Node/Vite para existir.

---

## Estrutura sugerida no projeto Rails

```text
app/
  controllers/
    graphs_controller.rb
    api/
      graphs_controller.rb
  services/
    graph/
      dataset_builder.rb
      note_serializer.rb
      link_serializer.rb
      tag_serializer.rb
  javascript/
    controllers/
      graph_controller.js
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
  views/
    graphs/
      show.html.erb
```

Regras:

- `GET /graph` renderiza a página HTML do grafo.
- `GET /api/graph` existe apenas como endpoint de dados do novo grafo.
- Os nomes acima podem variar, mas a separação de responsabilidades deve permanecer.
- O endpoint antigo e a view antiga não devem ser usados como base de evolução.

---

## Modelo de dados assumido

### note_links

- `id`: UUID PK
- `src_note_id`: UUID FK -> notes
- `dst_note_id`: UUID FK -> notes
- `hier_role`: enum nullable
  - `target_is_parent`
  - `target_is_child`
  - `same_level`
  - `null` => unclassified
- `created_in_revision_id`: UUID FK -> note_revisions
- `context`: jsonb
- `created_at`: timestamp

### tags

- `id`: UUID PK
- `name`: string UNIQUE NOT NULL
- `color_hex`: string
- `icon`: string nullable
- `tag_scope`: enum (`note`, `link`, `both`)
- `created_at`: timestamp

### note_tags

- `note_id`: UUID FK -> notes
- `tag_id`: UUID FK -> tags
- `created_at`: timestamp

### link_tags

- `note_link_id`: UUID FK -> note_links
- `tag_id`: UUID FK -> tags
- `created_at`: timestamp

---

## Premissas de domínio

1. Existe apenas um link por par dirigido `src_note_id -> dst_note_id`.
2. O grafo é dirigido simples.
3. A direção lógica da aresta é sempre `src_note_id -> dst_note_id`.
4. O banco fornece `hier_role`; rótulos visuais como `father`, `child` e `brother` são derivados na aplicação.
5. Esses papéis não são inferidos em tempo real no cliente.
6. A relação de tags é N:N para nós e links.
7. O filtro visual por tags deve aceitar:
   - ordem arbitrária definida pelo usuário
   - corte Top-N
   - modo mostrando tudo
   - modo destacando apenas o conjunto relevante
8. O conteúdo textual da nota não deve ser carregado integralmente por padrão só para desenhar o grafo.
9. Tooltips e sidebars devem usar resumo leve, nunca a revisão completa como payload obrigatório inicial.

---

## Contrato da API

### Endpoint

`GET /api/graph`

### Forma do payload

O backend deve retornar dataset normalizado, não um SVG pré-processado e não um grafo já “achatado” na forma da UI atual.

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

### DTOs de entrada

```ts
export interface NoteDTO {
  id: string;
  slug: string;
  title?: string;
  excerpt?: string | null;
  updated_at?: string;
  created_at?: string;
}

export interface NoteLinkDTO {
  id: string;
  src_note_id: string;
  dst_note_id: string;
  hier_role: "target_is_parent" | "target_is_child" | "same_level" | null;
  context?: unknown;
  created_at?: string;
}

export interface TagDTO {
  id: string;
  name: string;
  color_hex: string | null;
  icon?: string | null;
  tag_scope: "note" | "link" | "both";
}

export interface NoteTagDTO {
  note_id: string;
  tag_id: string;
}

export interface LinkTagDTO {
  note_link_id: string;
  tag_id: string;
}
```

### Regras do payload

- `excerpt` deve ser curto e derivado do conteúdo indexável da nota.
- Não enviar `content_markdown` completo no carregamento inicial do grafo.
- O cliente deve conseguir montar todos os índices auxiliares só com esse dataset.
- Registros inconsistentes podem ser omitidos, mas o backend deve logar isso.
- O endpoint deve responder apenas com dados autorizados ao usuário corrente.

---

## Tipos internos do grafo

```ts
export type HierRole =
  | "target_is_parent"
  | "target_is_child"
  | "same_level"
  | null;

export type NodeFilterState = "normal" | "ghost" | "hidden";
export type EdgeFilterState = "normal" | "hidden";

export type EdgeVisualKind = "line" | "arrow";
export type EdgeArrowSide = "none" | "source" | "target";

export interface NodeAttrs {
  id: string;
  slug: string;
  label: string;
  excerpt: string | null;

  x: number;
  y: number;
  size: number;

  baseColor: string;
  color?: string;
  hidden?: boolean;

  noteTags: string[];

  isFocused?: boolean;
  isHovered?: boolean;
  filterState?: NodeFilterState;

  depthFromFocus?: 0 | 1 | 2 | 999;
  hasVisibleIncidentEdge?: boolean;
}

export interface EdgeAttrs {
  id: string;

  hierRole: HierRole;

  baseColor: string;
  color?: string;
  size: number;
  hidden?: boolean;

  linkTags: string[];

  filterState?: EdgeFilterState;

  visualKind?: EdgeVisualKind;
  visualArrowSide?: EdgeArrowSide;

  srcPadding?: number;
  dstPadding?: number;

  isFocusDepth1?: boolean;
  isFocusDepth2?: boolean;
}
```

Tipo do grafo:

```ts
DirectedGraph<NodeAttrs, EdgeAttrs>
```

---

## Construção do grafo

### Regras

- cada `NoteDTO` vira um nó
- cada `NoteLinkDTO` vira uma aresta
- a key da aresta deve ser o `id` do link
- o `source` da aresta é `src_note_id`
- o `target` da aresta é `dst_note_id`

### Regras de sanidade

- ignorar arestas cujo `source` ou `target` não existam
- logar inconsistências
- impedir criação duplicada de arestas entre o mesmo `source -> target`
- validar payload antes de montar o grafo

### Índices auxiliares

Criar e manter:

- `tagsByNoteId: Map<string, string[]>`
- `tagsByLinkId: Map<string, string[]>`
- `tagMetaById: Map<string, TagDTO>`
- `outEdgesByNodeId: Map<string, string[]>`
- `inEdgesByNodeId: Map<string, string[]>`
- `neighborDepth1Cache: Map<string, Set<string>>`
- `neighborDepth2Cache: Map<string, Set<string>>`

Regras:

- recalcular apenas ao carregar um dataset novo
- ou quando o dataset sofrer mutação estrutural
- não recalcular isso em hover

---

## Semântica visual dos links

### Direção lógica

Sempre:

- `src_note_id -> dst_note_id`

### Regra visual por `hier_role`

#### `target_is_parent`

- tipo visual: `arrow`
- a seta aponta para o father
- como o target é o parent, a seta fica do lado do `target`
- `visualArrowSide = "target"`

#### `target_is_child`

- tipo visual: `arrow`
- a seta aponta para o father
- como o target é o child, o father está no `source`
- `visualArrowSide = "source"`

#### `same_level`

- tipo visual: `line`
- sem seta

#### `null`

- tipo visual: `line`
- sem seta

### Regra de gap

Independentemente de ter seta ou não, a aresta deve:

- manter um padding normal no lado do `src`
- manter um padding maior no lado do `dst`

Objetivo:

- reforçar visualmente qual ponta é `dst`
- diferenciar `src` e `dst` mesmo em links sem seta

### Parâmetros iniciais sugeridos

- `srcPadding = 4`
- `dstPadding = 10`
- `arrowHeadLength = 8`
- `arrowHeadWidth = 6`

### Observação

A implementação padrão de arestas do Sigma não cobre bem:

- seta no lado do source
- seta no lado do target de forma seletiva
- gap assimétrico por extremidade

Portanto, prever desde o início um custom edge renderer.

---

## Semântica visual dos nós

### Estados

```ts
type NodeFilterState = "normal" | "ghost" | "hidden";
```

#### `normal`

- pertence ao filtro ativo por tags
- cor plena
- opacidade normal
- label pode aparecer conforme regras de zoom, foco e hover

#### `ghost`

- não pertence ao filtro
- mas é necessário como contexto porque possui aresta visível incidente
- cor dessaturada
- menor destaque
- sem label por padrão

#### `hidden`

- não pertence ao filtro
- não possui aresta visível incidente
- deve sair da renderização

---

## Filtro por tags

### Conceito

Existe uma lista de tags ativa e ordenada pelo usuário:

```ts
activeTagsOrdered: string[]
```

Existe um corte:

```ts
topN: number
```

As tags consideradas no filtro são:

```ts
highlightTags = activeTagsOrdered.slice(0, topN)
```

### Regra de cor

A cor efetiva de um item é a cor da primeira tag da lista ordenada que também pertença ao item.

### Função sugerida

```ts
export function resolvePriorityTag(
  itemTags: string[],
  activeTagsOrdered: string[],
  topN: number
): string | null {
  const allowed = activeTagsOrdered.slice(0, topN);
  const itemTagSet = new Set(itemTags);

  for (const tagId of allowed) {
    if (itemTagSet.has(tagId)) return tagId;
  }

  return null;
}
```

### Modos de filtro

- `all`: tudo visível
- `focused-tags`: apenas arestas e nós relevantes ao conjunto de tags; contexto residual pode virar `ghost`

---

## Foco e profundidade

Ao clicar em um nó:

1. esse nó vira `focusedNodeId`
2. seu tooltip torna-se persistente
3. o tooltip persistente anterior é fechado
4. a vizinhança de profundidade 1 e 2 pode receber estilo especial
5. o layout pode sofrer reorganização local, não reset global completo

### Organização hierárquica local desejada

Quando existir `focusedNodeId`, o relayout local deve privilegiar leitura estrutural:

- profundidade 1:
  - `father` tende para cima
  - `brother` tende para o meio do eixo vertical
  - `child` tende para baixo
  - `null` fica mais distante do nó em foco do que os demais
  - `src` tende para a esquerda
  - `dst` tende para a direita
- profundidade 2:
  - tenta preservar essa leitura
  - fica um pouco mais distante do foco do que a profundidade 1 para ajudar a visualização

Observação:
- a organização é local e assistida, não precisa virar um layout rígido de árvore.

Estado mínimo sugerido:

```ts
interface GraphUiState {
  focusedNodeId: string | null;
  pinnedTooltipNodeId: string | null;
  hoveredNodeId: string | null;
  activeTagsOrdered: string[];
  topN: number;
  filterMode: "all" | "focused-tags";
}
```

---

## Tooltip e navegação

Requisitos:

- hover abre tooltip transitório
- clique fixa tooltip
- clique em outro nó troca o tooltip fixado
- clique fora limpa foco e tooltip persistente
- clique no CTA do tooltip abre a nota para leitura ou edição

Regras de implementação:

- tooltip como overlay HTML
- não desenhar tooltip dentro do canvas/WebGL do Sigma
- posicionar o tooltip com coordenadas projetadas do nó na viewport
- o tooltip deve usar `title`, `excerpt` e ações de navegação

Estado atual aceito:

- tooltip HTML em overlay
- hover transitório e clique persistente
- clique no tooltip navega para a nota
- não é obrigatório expor múltiplos CTAs se a navegação principal já estiver clara

---

## Sidebar e toolbar

A UI precisa, no mínimo, de:

- controle da ordem de tags
- seleção Top-N
- modo `all` vs `focused-tags`
- filtros por `hier_role`
- seleção de profundidade
- reset de foco

---

## Performance e limites

O documento original estava incompleto neste ponto. Para esta feature no NeuraMD, considerar obrigatório:

- endpoint com eager loading e serialização previsível
- nenhum N+1 no carregamento do dataset
- payload inicial leve o suficiente para uso interativo
- possibilidade futura de recorte do dataset sem quebrar o contrato
- layout e índices recalculados só quando necessário

Se o volume crescer muito, a evolução aceitável é:

- recorte por subgrafo
- carregamento incremental
- cache do dataset serializado

Sem mudar a semântica do contrato.

---

## Itens que precisam de correção em relação ao documento antigo

- remover Node.js como requisito de backend
- remover Vite como requisito arquitetural
- substituir `content` completo por `excerpt` no dataset inicial
- deixar explícito que o endpoint atual não é baseline
- deixar explícito que `hier_role` vem do banco, mas rótulos amigáveis são derivados
- deixar explícito que o novo contrato da API é normalizado

---

## Critérios de aceite

- o novo `/graph` não depende da implementação atual
- o novo `/api/graph` segue o contrato normalizado deste documento
- o grafo suporta foco por nó, profundidade e filtro por tags
- a semântica visual de `hier_role` é respeitada
- tooltip é HTML, persistente no clique e transitório no hover
- navegação para a nota funciona a partir do nó e do tooltip
- a UI continua integrada ao Rails, sem SPA paralela

---

## Estratégia de implementação

1. definir o contrato do endpoint em Ruby
2. construir serializer/dataset builder dedicado
3. montar o cliente do grafo em módulos JS isolados
4. implementar renderer customizado de arestas
5. implementar foco, tooltip, filtros e sidebar
6. validar performance com dataset real

Esse documento é a fonte de verdade da reformulação do grafo no NeuraMD.
