import { useCallback, useState } from "react"
import { Route, Routes } from "react-router-dom"

import { CommandPalette } from "~/components/command/CommandPalette"
import { SearchPage } from "~/components/command/SearchPage"
import { useCommandHotkey } from "~/components/command/useCommandHotkey"
import { EditorPage } from "~/components/editor/EditorPage"
import { GraphPage } from "~/components/graph/GraphPage"
import { PrimaryNav } from "~/components/primary-nav/PrimaryNav"
import { TentaclePage } from "~/components/tentacles/TentaclePage"
import { TentaclesDashboard } from "~/components/tentacles/TentaclesDashboard"
import { PlaceholderSurface } from "~/shell/PlaceholderSurface"

export function Shell() {
  const [paletteOpen, setPaletteOpen] = useState(false)
  const openPalette = useCallback(() => setPaletteOpen(true), [])
  const closePalette = useCallback(() => setPaletteOpen(false), [])

  useCommandHotkey(openPalette)

  return (
    <div className="nm-shell">
      <PrimaryNav />
      <main className="nm-shell__main">
        <Routes>
          <Route path="/" element={<GraphPage />} />
          <Route path="/graph" element={<GraphPage />} />
          <Route path="/notes/:slug" element={<EditorPage />} />
          <Route path="/notes/:slug/tentacle" element={<TentaclePage />} />
          <Route path="/tentacles" element={<TentaclesDashboard />} />
          <Route path="/search" element={<SearchPage />} />
          <Route path="/settings/*" element={<PlaceholderSurface title="Configurações" note="Fase 6.2 traz as sub-tabs." />} />
          <Route path="*" element={<PlaceholderSurface title="Não encontrado" note="Rota não reconhecida pelo shell." />} />
        </Routes>
      </main>
      <CommandPalette open={paletteOpen} onClose={closePalette} />
    </div>
  )
}
