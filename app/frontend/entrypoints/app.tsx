import { StrictMode } from "react"
import { createRoot } from "react-dom/client"
import { BrowserRouter } from "react-router-dom"

import { Shell } from "~/shell/Shell"
import "~/styles/shell.css"

const mount = document.getElementById("app-root")
if (!mount) {
  throw new Error("NeuraMD shell: #app-root element missing")
}

createRoot(mount).render(
  <StrictMode>
    <BrowserRouter basename="/app">
      <Shell />
    </BrowserRouter>
  </StrictMode>
)
