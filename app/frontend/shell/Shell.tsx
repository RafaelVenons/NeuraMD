import { useCallback, useState } from "react"
import { Navigate, Route, Routes } from "react-router-dom"

import { CommandPalette } from "~/components/command/CommandPalette"
import { SearchPage } from "~/components/command/SearchPage"
import { useCommandHotkey } from "~/components/command/useCommandHotkey"
import { EditorPage } from "~/components/editor/EditorPage"
import { GraphPage } from "~/components/graph/GraphPage"
import { PrimaryNav } from "~/components/primary-nav/PrimaryNav"
import { AiOpsTab } from "~/components/settings/AiOpsTab"
import { FileImportsTab } from "~/components/settings/FileImportsTab"
import { PlaceholderTab } from "~/components/settings/PlaceholderTab"
import { PropertyDefinitionsTab } from "~/components/settings/PropertyDefinitionsTab"
import { SettingsLayout } from "~/components/settings/SettingsLayout"
import { TagsTab } from "~/components/settings/TagsTab"
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
          <Route path="/settings" element={<SettingsLayout />}>
            <Route index element={<Navigate to="properties" replace />} />
            <Route path="properties" element={<PropertyDefinitionsTab />} />
            <Route path="imports" element={<FileImportsTab />} />
            <Route path="ai" element={<AiOpsTab />} />
            <Route path="tts" element={<PlaceholderTab title="TTS" note="O player fixed-bottom chega no slice 6.4." />} />
            <Route path="tags" element={<TagsTab />} />
          </Route>
          <Route path="*" element={<PlaceholderSurface title="Não encontrado" note="Rota não reconhecida pelo shell." />} />
        </Routes>
      </main>
      <CommandPalette open={paletteOpen} onClose={closePalette} />
    </div>
  )
}
