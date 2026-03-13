# Color Recommendation Prompt

Use este prompt no Claude Code para recomendar a próxima cor de uma paleta.

---

## Comando slash sugerido: `/cor`

Cole no arquivo `.claude/commands/cor.md` do seu projeto:

```
Analise a paleta de cores abaixo e recomende a cor N+1.

Paleta atual: $ARGUMENTS

Responda APENAS com um objeto JSON no seguinte formato (sem markdown, sem explicação):
{
  "recomendacao": {
    "hex": "#XXXXXX",
    "hsl": { "h": 0, "s": 0, "l": 0 },
    "nome": "nome descritivo da cor",
    "motivo": "por que essa cor complementa a paleta",
    "harmonia": "tipo de harmonia aplicada (complementar/triádica/análoga/split/tetrádica)",
    "wcag_contraste_fundo_escuro": "AA / AAA / FAIL",
    "wcag_contraste_fundo_claro": "AA / AAA / FAIL"
  },
  "alternativas": [
    { "hex": "#XXXXXX", "hsl": { "h": 0, "s": 0, "l": 0 }, "motivo": "..." },
    { "hex": "#XXXXXX", "hsl": { "h": 0, "s": 0, "l": 0 }, "motivo": "..." }
  ],
  "paleta_completa": ["#cor1", "#cor2", "...", "#XXXXXX"]
}

Critérios de recomendação:
- Priorizar contraste adequado entre as cores existentes
- Manter coerência de saturação e brilho com a paleta
- Indicar a harmonia cromática usada
- Oferecer 2 alternativas com abordagens diferentes
```

---

## Exemplo de uso no terminal

```bash
claude "/cor #1A1A2E, #16213E, #0F3460"
```

### Saída esperada:
```json
{
  "recomendacao": {
    "hex": "#E94560",
    "hsl": { "h": 350, "s": 79, "l": 56 },
    "nome": "Vermelho Coral",
    "motivo": "Complementar aos azuis frios da paleta, gera alto contraste e ponto focal",
    "harmonia": "complementar",
    "wcag_contraste_fundo_escuro": "AA",
    "wcag_contraste_fundo_claro": "FAIL"
  },
  "alternativas": [
    { "hex": "#533483", "hsl": { "h": 270, "s": 43, "l": 36 }, "motivo": "Análoga, mantém família fria com variação de tom" },
    { "hex": "#0F7173", "hsl": { "h": 181, "s": 76, "l": 25 }, "motivo": "Triádica, introduz verde-azulado sem quebrar a harmonia escura" }
  ],
  "paleta_completa": ["#1A1A2E", "#16213E", "#0F3460", "#E94560"]
}
```

---

## Integração com a ferramenta Chroma

Após receber a resposta JSON do Claude Code:

1. Abra `color-tool.html` no browser
2. Na aba **Harmonia de Cores**, ajuste os sliders de Saturação/Brilho
   para corresponder ao HSL recomendado
3. Use o círculo cromático para explorar variações no mesmo espectro
4. Na aba **Tons & Sombras**, refine claridade/escuridão preservando o matiz
5. Exporte o CSS final com o botão **Exportar CSS**

---

## Uso via CLAUDE.md (contexto permanente)

Adicione ao `CLAUDE.md` do seu projeto para que o Claude Code sempre
considere a paleta ao sugerir estilos:

```markdown
## Paleta de Cores do Projeto

Cores definidas:
- `--color-primary`: #1A1A2E
- `--color-secondary`: #16213E
- `--color-accent`: #0F3460

Regras:
- Novas cores devem manter harmonia com a paleta acima
- Sempre verificar contraste WCAG AA mínimo
- Saturação base: 70-80%, Brilho base: 40-60%
- Para sugerir nova cor, usar o critério de harmonia: complementar
```
