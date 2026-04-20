import { NavLink, Outlet } from "react-router-dom"

const tabs = [
  { path: "properties", label: "Propriedades" },
  { path: "imports", label: "Imports" },
  { path: "ai", label: "IA ops" },
  { path: "tts", label: "TTS" },
  { path: "tags", label: "Tags" }
]

export function SettingsLayout() {
  return (
    <section className="nm-settings">
      <header className="nm-settings__header">
        <h1>Configurações</h1>
        <nav className="nm-settings__tabs">
          {tabs.map((tab) => (
            <NavLink
              key={tab.path}
              to={tab.path}
              end
              className={({ isActive }) =>
                isActive ? "nm-settings__tab is-active" : "nm-settings__tab"
              }
            >
              {tab.label}
            </NavLink>
          ))}
        </nav>
      </header>
      <div className="nm-settings__body">
        <Outlet />
      </div>
    </section>
  )
}
