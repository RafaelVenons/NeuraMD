# Prometheus + Grafana stack for NeuraMD

Scrape config for the `neuramd-metrics-exporter.service` daemon.

## Deploy

Ops responsibility. Minimal standalone stack via `podman-compose` (or Docker):

```yaml
# deploy/prometheus/compose.yml (not checked in — provision locally)
services:
  prometheus:
    image: prom/prometheus:latest
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - prom_data:/prometheus
    ports:
      - "127.0.0.1:9090:9090"
    restart: unless-stopped

  grafana:
    image: grafana/grafana:latest
    volumes:
      - grafana_data:/var/lib/grafana
      - ./grafana/provisioning:/etc/grafana/provisioning:ro
      - ./grafana/dashboards:/var/lib/grafana/dashboards:ro
    ports:
      - "127.0.0.1:3001:3000"
    restart: unless-stopped
    environment:
      - GF_SECURITY_ADMIN_PASSWORD__FILE=/run/secrets/grafana_admin

volumes:
  prom_data:
  grafana_data:
```

Caddy rule to expose Grafana on `grafana.airch.local` (TLS internal):

```caddy
grafana.airch.local {
  tls internal
  reverse_proxy 127.0.0.1:3001
}
```

## Local smoke test (without Prometheus running)

```bash
# In one shell: start the exporter
bin/neuramd-metrics-exporter

# In another: scrape it
curl -s http://127.0.0.1:9100/metrics
curl -s http://127.0.0.1:9100/health
```

POST an event (requires `NEURAMD_DEPLOY_TOKEN` or token file):

```bash
curl -sf -X POST \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"outcome":"clear"}' \
  http://127.0.0.1:9100/event/deploy
```

## Metrics exposed (T7 phase)

| Metric | Type | Labels | Source |
|--------|------|--------|--------|
| `neuramd_note_count` | gauge | — | `Note.active.count` |
| `neuramd_note_deleted_count` | gauge | — | `Note.where.not(deleted_at: nil).count` |
| `neuramd_agent_messages_pending` | gauge | — | `AgentMessage.where(delivered_at: nil).count` |
| `neuramd_deploy_count_total` | counter | `outcome` | `/event/deploy` log |
| `neuramd_tentacles_spawned_total` | counter | — | `/event/tentacle_spawn` log |
| `neuramd_tentacles_exited_total` | counter | `reason` | `/event/tentacle_exit` log |
| `neuramd_transcripts_persisted_total` | counter | `outcome` | `/event/transcript_persist` log |

Future chunks will add AI and SolidQueue collectors; wire main-app hooks
(TentacleRuntime.start / TranscriptService.persist) to POST events to
the exporter; and author a Grafana dashboard under `deploy/grafana/`.

## Followup ops

- Instalar `prom/prometheus` + `grafana/grafana` via podman-compose
- Provisionar token file `/home/rafael/.config/neuramd/deploy.token` compartilhado com o drain endpoint
- Abrir firewall interno entre Prometheus e exporter (ambos em localhost → nada a fazer, mesma máquina)
- Habilitar `neuramd-metrics-exporter.service` no systemd: `systemctl daemon-reload && systemctl enable --now neuramd-metrics-exporter`
