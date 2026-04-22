import { useEffect, useMemo, useState, useSyncExternalStore } from "react"
import { NavLink } from "react-router-dom"

import { deriveSessionTabs, type SessionTab } from "~/components/primary-nav/sessionTabs"
import type { TentacleSession, TentacleSessionsIndex } from "~/components/tentacles/types"
import { TentacleRuntimeWatcherMount } from "~/components/tentacles/useTentacleRuntimeWatcher"
import { ApiError } from "~/runtime/errors"
import { fetchJson } from "~/runtime/fetchJson"
import { runtimeStateStore } from "~/runtime/runtimeStateStore"

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

const SESSIONS_POLL_INTERVAL_MS = 15_000

export function PrimaryNav() {
  const sessions = useLiveSessions()
  const runtimeStates = useSyncExternalStore(
    runtimeStateStore.subscribe,
    runtimeStateStore.getSnapshot,
    runtimeStateStore.getSnapshot
  )
  const tabs = useMemo(
    () => deriveSessionTabs({ sessions, runtimeStates }),
    [sessions, runtimeStates]
  )
  const attentionCount = tabs.reduce((n, tab) => (tab.needsAttention ? n + 1 : n), 0)

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
              title={
                item.to === "/tentacles" && attentionCount > 0
                  ? `${item.label} — ${attentionCount} aguardando você`
                  : item.label
              }
            >
              <span className="nm-primary-nav__short" aria-hidden>
                {item.short}
              </span>
              <span className="nm-primary-nav__label">{item.label}</span>
              {item.to === "/tentacles" && attentionCount > 0 ? (
                <span
                  className="nm-primary-nav__attention-dot"
                  aria-label={`${attentionCount} aguardando você`}
                />
              ) : null}
            </NavLink>
          </li>
        ))}
      </ul>

      {tabs.length > 0 ? (
        <>
          <div className="nm-primary-nav__divider" aria-hidden />
          <h2 className="nm-primary-nav__section-title">Sessões</h2>
          <ul className="nm-primary-nav__list nm-primary-nav__list--sessions">
            {tabs.map((tab) => (
              <SessionTabLink key={tab.id} tab={tab} />
            ))}
          </ul>
        </>
      ) : null}

      {sessions
        .filter((session) => session.alive)
        .map((session) => (
          <TentacleRuntimeWatcherMount key={session.tentacle_id} tentacleId={session.tentacle_id} />
        ))}
    </nav>
  )
}

function SessionTabLink({ tab }: { tab: SessionTab }) {
  if (!tab.slug) {
    return (
      <li>
        <span
          className={`nm-primary-nav__session is-disabled nm-primary-nav__session--${tab.state}`}
          title={tab.label}
        >
          <span className="nm-primary-nav__session-dot" aria-hidden />
          <span className="nm-primary-nav__session-label">{tab.label}</span>
        </span>
      </li>
    )
  }

  const to = `/notes/${encodeURIComponent(tab.slug)}/tentacle`
  const title = tab.needsAttention ? `${tab.label} — aguardando você` : tab.label

  return (
    <li>
      <NavLink
        to={to}
        className={({ isActive }) =>
          `nm-primary-nav__session nm-primary-nav__session--${tab.state}${
            isActive ? " is-active" : ""
          }${tab.needsAttention ? " is-attention" : ""}`
        }
        title={title}
      >
        <span className="nm-primary-nav__session-dot" aria-hidden />
        <span className="nm-primary-nav__session-label">{tab.label}</span>
      </NavLink>
    </li>
  )
}

const DISABLED_STATUSES = new Set([401, 403, 404])

function useLiveSessions(): TentacleSession[] {
  const [sessions, setSessions] = useState<TentacleSession[]>([])

  useEffect(() => {
    let cancelled = false
    let interval: number | null = null

    const clearInterval = () => {
      if (interval != null) {
        window.clearInterval(interval)
        interval = null
      }
    }

    const fetchOnce = async () => {
      try {
        const res = await fetchJson<TentacleSessionsIndex>("/api/tentacles/sessions")
        if (!cancelled) setSessions(res.sessions)
      } catch (error) {
        if (error instanceof ApiError && DISABLED_STATUSES.has(error.status)) {
          clearInterval()
        }
        // Otherwise keep polling — the dashboard surfaces transient errors.
      }
    }

    void fetchOnce()
    interval = window.setInterval(fetchOnce, SESSIONS_POLL_INTERVAL_MS)
    return () => {
      cancelled = true
      clearInterval()
    }
  }, [])

  return sessions
}
