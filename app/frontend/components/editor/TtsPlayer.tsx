import { useEffect, useState } from "react"

import { fetchJson } from "~/runtime/fetchJson"

type TtsAsset = {
  id: string
  revision_id: string
  language: string | null
  voice: string | null
  provider: string | null
  format: string | null
  duration_ms: number | null
  audio_url: string | null
  created_at: string | null
}

type Payload = {
  active_asset: TtsAsset | null
  library_count: number
}

type Props = {
  slug: string
  noteTitle: string
}

export function TtsPlayer({ slug, noteTitle }: Props) {
  const [asset, setAsset] = useState<TtsAsset | null>(null)
  const [libraryCount, setLibraryCount] = useState(0)
  const [hidden, setHidden] = useState(false)

  useEffect(() => {
    fetchJson<Payload>(`/api/notes/${encodeURIComponent(slug)}/tts`)
      .then((res) => {
        setAsset(res.active_asset)
        setLibraryCount(res.library_count)
      })
      .catch(() => {
        setAsset(null)
      })
    setHidden(false)
  }, [slug])

  if (hidden) return null
  if (!asset?.audio_url) return null

  return (
    <aside className="nm-tts-player" aria-label={`Áudio TTS de ${noteTitle}`}>
      <div className="nm-tts-player__meta">
        <strong>{noteTitle}</strong>
        <span className="nm-tts-player__muted">
          {asset.provider || "tts"} · {asset.voice || "voz padrão"}
          {libraryCount > 1 ? ` · ${libraryCount} no histórico` : ""}
        </span>
      </div>
      <audio
        className="nm-tts-player__audio"
        controls
        src={asset.audio_url}
        preload="metadata"
      />
      <button
        type="button"
        className="nm-tts-player__close"
        onClick={() => setHidden(true)}
        title="Esconder player"
      >
        ×
      </button>
      <button
        type="button"
        className="nm-tts-player__karaoke"
        title="Karaoke word-sync ainda fica off na Fase 6"
        disabled
      >
        karaoke
      </button>
    </aside>
  )
}
