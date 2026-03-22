# Especificação da UI e mecânica da Queue de serviços

## Objetivo

Implementar uma queue visual de solicitações assíncronas para notas. Cada item da fila representa uma solicitação de serviço aplicada a uma nota. A prioridade principal é garantir:

- visualização compacta e clara dos itens;
- ordenação manual por prioridade via drag and drop;
- estados visuais inequívocos;
- ausência de duplicação visual durante drag;
- comportamento consistente de cancelamento, erro e retry.

---

## Tipos de serviço

Atualmente existem 4 tipos de serviço que podem entrar na fila:

- Revisão
- Markdown
- Tradução
- Criação

Cada item da fila deve carregar pelo menos:

- `serviceType`
- `noteTitle`
- `modelName`
- `status`
- `queuePosition`
- `canCancel`
- `canRetry`

---

## Estrutura visual de cada item da fila

Cada item da queue deve ser exibido como um **balão/card compacto**, com layout flutuante e largura adaptativa ao conteúdo.

### Informações obrigatórias no balão

O balão deve exibir exatamente 3 informações principais:

1. **Serviço**  
2. **Título da nota**  
3. **Modelo usado**

### Regras de layout do balão

- O balão **não deve ter largura horizontal fixa rígida**.
- Deve ser **compacto**, ocupando apenas o espaço necessário dentro dos limites visuais do container.
- O balão deve parecer um elemento **floating**, não uma linha de tabela.
- O conteúdo deve estar organizado em pilha vertical:
  - linha 1: nome curto do serviço/status
  - linha 2: título da nota
  - linha 3: modelo usado
- O título da nota pode quebrar linha se necessário, mas o componente deve continuar compacto.
- O modelo usado deve ser visível, porém com menor destaque que o título.
- O botão de cancelar deve ficar em destaque visual no canto superior direito.

---

## Estados da fila

Cada item pode estar em um dos estados abaixo.

### 1. Pendente na fila
Estado da solicitação que ainda **não começou a ser processada**.

- borda: **cinza**
- botão vermelho com `X`: **visível**
- item pode ser reordenado
- item pode ser cancelado

### 2. Em processamento
Estado da solicitação que está sendo executada no momento.

- borda: **amarela**
- botão vermelho com `X`: **visível**
- idealmente não permitir duplicação visual durante atualizações de estado
- item ainda pode ser cancelado

### 3. Processado com sucesso
Estado final de sucesso.

- borda: **verde**
- botão vermelho com `X`: **não visível**
- item não pode mais ser cancelado
- item não precisa mais participar da priorização da parte pendente da fila

### 4. Erro
Estado final de falha.

- borda: **vermelha**
- botão vermelho com `X`: **não é o foco principal aqui**
- deve existir ação de **tentar novamente** (`retry`)
- ao clicar em retry, o item deve voltar para a fila com comportamento consistente definido pelo sistema

---

## Semântica curta do nome do serviço

O texto do serviço deve ser sucinto e mudar conforme o estado, preferencialmente em uma palavra ou termo curto.

### Exemplos esperados

#### Revisão
- pendente: `Revisar`
- processando: `Revisando`
- sucesso: `Revisado`

#### Markdown
- pendente: `Markdown`
- processando: `Markdown...` ou outro rótulo curto equivalente
- sucesso: `Markdown`

#### Tradução
- pendente: `Traduzir`
- processando: `Traduzindo`
- sucesso: `Traduzido`

#### Criação
- pendente: `Criar`
- processando: `Criando`
- sucesso: `Criado`

### Regra
A UI deve permitir mapear o rótulo exibido com base em:

- `serviceType`
- `status`

Idealmente isso deve ser centralizado em uma função de apresentação, e não espalhado no componente.

---

## Mecânica da queue

## Direção visual da fila

A queue é **vertical**.

### Regra de ordem visual

- os itens **mais prioritários / na frente da fila** devem ficar **mais abaixo**
- os itens **menos prioritários / mais para trás** devem ficar **mais acima**

Em outras palavras:

- base da coluna = frente da fila
- topo da coluna = final da fila

Isso é intencional e deve ser preservado.

---

## Scroll

A área da queue possui uma altura máxima definida pelo layout da aplicação.

### Regra
Quando a quantidade de itens ultrapassar o espaço vertical disponível:

- deve surgir **scroll vertical**
- o scroll deve atuar apenas no container da fila
- a interação de drag and drop deve continuar funcionando corretamente mesmo com scroll

---

## Reordenação por prioridade

O usuário pode alterar a prioridade manualmente com **click and drag**.

### Objetivo
Permitir mudar a posição de itens ainda relevantes para processamento sem causar glitches visuais.

### Regras de drag and drop

- ao clicar e arrastar um item, deve ser possível reposicioná-lo entre outros itens
- enquanto o item está sendo arrastado:
  - **não pode aparecer duplicado em tela**
  - deve existir apenas:
    - o item arrastado (`drag preview`), e
    - o espaço reservado no destino (`placeholder`)
- os demais itens devem se mover com animação suave para abrir espaço
- ao arrastar para entre dois balões, a fila deve **abrir espaço visual** naquele ponto
- o item deve “encaixar” visualmente na posição de drop antes da confirmação final

### Restrições importantes

A reordenação deve afetar prioritariamente os itens que ainda fazem sentido para fila ativa, ou seja:

- pendentes
- opcionalmente o item em processamento, se a regra de negócio permitir

Itens concluídos com sucesso normalmente não devem interferir na priorização da fila pendente.

### Requisito visual importante
Evitar qualquer implementação em que o item original continue renderizado no lugar antigo enquanto uma cópia é arrastada. Deve haver placeholder, não duplicata real visível.

---

## Cancelamento

Itens ainda não finalizados podem ser cancelados.

### Regras

- exibir um botão vermelho com `X` no canto superior direito do balão
- o botão deve existir apenas para itens:
  - pendentes
  - em processamento
- ao cancelar:
  - remover o item da fila de forma consistente
  - se estiver em processamento, o sistema deve tentar abortar a tarefa
  - a UI deve refletir isso imediatamente, sem esperar processamento visual longo

### UX esperada
Ao cancelar, o item deve desaparecer com animação curta ou transição limpa, sem “salto” abrupto dos demais elementos.

---

## Retry após erro

Quando uma solicitação falha, o item entra em estado de erro.

### Regras

- a borda passa a ser vermelha
- deve existir uma ação clara de **tentar novamente**
- ao clicar em retry:
  - o item deve voltar para o fluxo da fila
  - o estado deve sair de erro
  - a nova posição na fila deve seguir a regra definida pela aplicação

### Recomendação de comportamento
Por padrão, ao dar retry, reinserir o item como **pendente** em posição coerente de prioridade, preferencialmente no trecho dos itens ainda não processados.

---

## Separação entre estado lógico e estado visual

A implementação deve separar claramente:

### Estado lógico
Exemplo:
- `queued`
- `processing`
- `success`
- `error`
- `cancelled`

### Estado visual derivado
Exemplo:
- cor da borda
- visibilidade do botão `X`
- visibilidade do botão `retry`
- rótulo curto do serviço
- possibilidade de arrastar

Isso evita inconsistências e simplifica manutenção.

---

## Regras visuais resumidas

### Borda do balão
- pendente: cinza
- processando: amarela
- sucesso: verde
- erro: vermelha

### Botões
- cancelar (`X` vermelho): apenas pendente e processando
- retry: apenas erro

### Conteúdo
- 1ª linha: rótulo curto do serviço/status
- 2ª linha: título da nota
- 3ª linha: modelo usado

---

## Requisitos de animação

As animações devem ser discretas e funcionais.

### Obrigatório
- movimentação suave dos itens ao reordenar
- placeholder abrindo espaço na posição de drop
- ausência de duplicação visual do item arrastado
- transição de entrada/saída de itens sem flicker
- atualização de borda e estado sem recriar o componente inteiro de forma brusca

### Não desejado
- teleporte visual
- duplicata temporária
- flicker ao trocar status
- reflow brusco sem animação

---

## Comportamento esperado da área da fila

A área da queue deve funcionar como uma coluna flutuante de itens compactos.

### Características
- layout vertical
- alinhamento consistente
- scroll vertical ao exceder altura disponível
- itens compactos e legíveis
- reordenação por drag and drop
- destaque visual forte do estado de cada item

---

## Critérios de aceitação

A implementação só deve ser considerada correta se atender aos pontos abaixo:

1. Cada item mostra:
   - serviço
   - título da nota
   - modelo usado

2. Os balões são compactos e não dependem de largura fixa rígida.

3. A cor da borda representa corretamente o estado:
   - cinza
   - amarela
   - verde
   - vermelha

4. O botão vermelho `X` só aparece em itens pendentes ou em processamento.

5. Itens com erro permitem retry.

6. A queue é vertical e a frente da fila fica embaixo.

7. Ao exceder a área disponível, aparece scroll vertical.

8. O usuário consegue reordenar a prioridade por drag and drop.

9. Durante o drag, não existe duplicação visível do mesmo item.

10. Ao arrastar entre dois itens, a fila abre espaço com animação.

11. Trocas de estado não causam flicker ou recriação visual agressiva.

---

## Sugestão de modelo mental para implementação

Pensar em três camadas:

### 1. Modelo de dados da queue
Responsável por:
- lista ordenada de itens
- status de cada item
- prioridade
- ações (cancel, retry, reorder)

### 2. Regras derivadas de apresentação
Responsável por:
- label curto do serviço
- cor da borda
- exibição do botão `X`
- exibição do botão de retry
- permissão de drag

### 3. Componente visual
Responsável por:
- render dos balões
- drag and drop com placeholder
- animações
- scroll container

---

## Pontos de atenção para evitar bugs

- Não usar índice visual simples como identidade do item; usar `id` estável.
- Durante drag, o item arrastado não pode permanecer renderizado também na posição original.
- Mudanças de status não devem quebrar a ordem da fila de forma inesperada.
- Cancelamento de item em processamento deve considerar corrida entre:
  - conclusão natural
  - abort
  - atualização tardia da resposta assíncrona
- Retry não deve duplicar a mesma solicitação se houver resposta antiga chegando atrasada.
- O scroll container não deve atrapalhar o cálculo da posição de drop.

---

## Resultado esperado

Uma queue vertical flutuante, compacta, clara e manipulável, em que o usuário entende rapidamente:

- o que cada item está fazendo;
- qual nota está envolvida;
- qual modelo está sendo usado;
- o estado atual de cada solicitação;
- e consegue repriorizar, cancelar ou reenfileirar itens com segurança visual.
