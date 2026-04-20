import { Route, Routes } from "react-router-dom"

import { EditorPage } from "~/components/editor/EditorPage"
import { GraphPage } from "~/components/graph/GraphPage"
import { PrimaryNav } from "~/components/primary-nav/PrimaryNav"
import { PlaceholderSurface } from "~/shell/PlaceholderSurface"

export function Shell() {
  return (
    <div className="nm-shell">
      <PrimaryNav />
      <main className="nm-shell__main">
        <Routes>
          <Route path="/" element={<GraphPage />} />
          <Route path="/graph" element={<GraphPage />} />
          <Route path="/notes/:slug" element={<EditorPage />} />
          <Route path="/tentacles" element={<PlaceholderSurface title="Tentáculos" note="Fase 5 traz o dashboard multi." />} />
          <Route path="/search" element={<PlaceholderSurface title="Busca" note="Fase 6 habilita o Cmd+K." />} />
          <Route path="/settings/*" element={<PlaceholderSurface title="Configurações" note="Fase 6 traz as sub-tabs." />} />
          <Route path="*" element={<PlaceholderSurface title="Não encontrado" note="Rota não reconhecida pelo shell." />} />
        </Routes>
      </main>
    </div>
  )
}
