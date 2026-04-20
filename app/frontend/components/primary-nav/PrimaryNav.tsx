import { NavLink } from "react-router-dom"

type NavItem = {
  to: string
  label: string
  short: string
}

const ITEMS: NavItem[] = [
  { to: "/graph", label: "Grafo", short: "GR" },
  { to: "/notes", label: "Notas", short: "NT" },
  { to: "/tentacles", label: "Tentáculos", short: "TC" },
  { to: "/search", label: "Busca", short: "BC" },
  { to: "/settings", label: "Configurações", short: "CF" },
]

export function PrimaryNav() {
  return (
    <nav className="nm-primary-nav" aria-label="Navegação principal">
      <div className="nm-primary-nav__brand" aria-hidden>
        NM
      </div>
      <ul className="nm-primary-nav__list">
        {ITEMS.map((item) => (
          <li key={item.to}>
            <NavLink
              to={item.to}
              className={({ isActive }) =>
                `nm-primary-nav__link${isActive ? " nm-primary-nav__link--active" : ""}`
              }
              title={item.label}
            >
              <span className="nm-primary-nav__short" aria-hidden>
                {item.short}
              </span>
              <span className="nm-primary-nav__label">{item.label}</span>
            </NavLink>
          </li>
        ))}
      </ul>
    </nav>
  )
}
