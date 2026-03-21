# NeuraMD

## AIrch watcher

O stack em [docker-compose.airch.yml](/home/venom/projects/NeuraMD/docker-compose.airch.yml) agora sobe um watcher real em Python para processar jobs assíncronos via filesystem compartilhado.

### Pastas observadas

- `exchange/inbound`: entrada de jobs `.json`
- `exchange/outbound`: resultado final por job
- `exchange/archive/processed`: cópia arquivada de jobs concluídos
- `exchange/archive/failed`: cópia arquivada de jobs que falharam no provider
- `exchange/archive/invalid`: jobs inválidos
- `exchange/status/status.json`: estado completo do watcher
- `exchange/status/waybar.json`: payload pronto para `custom/*` do Waybar

### Formato mínimo do job

```json
{
  "id": "job-123",
  "capability": "grammar_review",
  "text": "teh texto",
  "language": "pt-BR",
  "model": "qwen2.5:1.5b",
  "metadata": {
    "source": "manual-test"
  }
}
```

Campos suportados:

- `id`: opcional, mas recomendado
- `capability`: `grammar_review`, `suggest` ou `rewrite`
- `text`: obrigatório
- `language`: opcional
- `model`: opcional; usa `OLLAMA_MODEL` por padrão
- `metadata`: opcional; volta no `outbound`

### Saída para Waybar

O watcher mantém [script/airch_watcher.py](/home/venom/projects/NeuraMD/script/airch_watcher.py) em execução contínua e também aceita leitura pontual:

```bash
python3 script/airch_watcher.py status
python3 script/airch_watcher.py waybar
```

`waybar` retorna JSON estável com:

- `text`
- `tooltip`
- `class`
- `alt`
- `percentage`

Isso permite usar retorno direto no `return-type: "json"` sem parser intermediário.

### Exemplo de módulo no Waybar

```json
{
  "custom/airch": {
    "format": "{}",
    "return-type": "json",
    "interval": 2,
    "exec": "cat /mnt/neuramd-share/exchange/status/waybar.json",
    "on-click": "foot -e sh -lc 'sed -n \"1,220p\" /mnt/neuramd-share/exchange/status/status.json; printf \"\\n\"; read -r _'"
  }
}
```

Arquivos prontos no repositório:

- [airch.config.jsonc](/home/venom/projects/NeuraMD/script/waybar/airch.config.jsonc)
- [airch.style.css](/home/venom/projects/NeuraMD/script/waybar/airch.style.css)

O watcher emite as classes:

- `idle`
- `busy`
- `error`
- `offline`

Se preferir não depender do arquivo já gerado:

```json
{
  "custom/airch": {
    "format": "{}",
    "return-type": "json",
    "interval": 2,
    "exec": "python3 /caminho/para/NeuraMD/script/airch_watcher.py waybar"
  }
}
```

### Variáveis de ambiente

Veja [.env.example](/home/venom/projects/NeuraMD/.env.example):

- `OLLAMA_API_BASE`
- `OLLAMA_MODEL`
- `AI_WATCHER_POLL_INTERVAL`
- `AI_WATCHER_HEALTH_TIMEOUT`
- `AI_WATCHER_REQUEST_TIMEOUT`
- `AI_WATCHER_TOOLTIP_JOBS`
