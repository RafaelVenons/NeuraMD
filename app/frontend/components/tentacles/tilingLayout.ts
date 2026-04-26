import type { RuntimeState } from "~/runtime/runtimeStateMachine"
import type { RuntimeStateSnapshot } from "~/runtime/runtimeStateStore"
import type { TentacleSession } from "~/components/tentacles/types"

const HARD_CAP = 16
const WALL_THRESHOLD = 10
const MIN_TILE_W = 520
const MIN_TILE_H = 220
const TABLET_BREAKPOINT = 1280
const MOBILE_BREAKPOINT = 768
const GOLDEN_LEFT = 0.62
const GOLDEN_RIGHT = 0.38

export type TilingTile = {
  kind: "terminal"
  session: TentacleSession
  weight: number
  col: number
  row: number
  colSpan: number
  rowSpan: number
}

export type TilingCard = {
  kind: "card"
  session: TentacleSession
}

export type TilingSlot = {
  col: number
  row: number
  colSpan: number
  rowSpan: number
}

export type TilingLayout = {
  tiles: TilingTile[]
  cards: TilingCard[]
  miniGraphSlot: TilingSlot | null
  columns: number[]
  rows: number[]
  hasMore: boolean
}

type Viewport = { width: number; height: number }

type Input = {
  sessions: TentacleSession[]
  focusedId: string | null
  runtimeStates: RuntimeStateSnapshot
  viewport: Viewport
}

function priorityRank(
  session: TentacleSession,
  index: number,
  focusedId: string | null,
  runtimeStates: RuntimeStateSnapshot
): { tier: number; at: number; index: number } {
  const entry = runtimeStates[session.tentacle_id]
  const state: RuntimeState | "unknown" = entry?.state ?? "unknown"
  const at = entry?.at ?? 0
  const isFocused = session.tentacle_id === focusedId
  let tier = 3
  if (state === "needs_input") tier = 0
  else if (state === "processing") tier = 1
  else if (isFocused) tier = 2
  return { tier, at, index }
}

function sortByPriority(
  sessions: TentacleSession[],
  focusedId: string | null,
  runtimeStates: RuntimeStateSnapshot
): TentacleSession[] {
  return sessions
    .map((session, index) => ({
      session,
      rank: priorityRank(session, index, focusedId, runtimeStates),
    }))
    .sort((a, b) => {
      if (a.rank.tier !== b.rank.tier) return a.rank.tier - b.rank.tier
      if (a.rank.at !== b.rank.at) return b.rank.at - a.rank.at
      return a.rank.index - b.rank.index
    })
    .map(({ session }) => session)
}

type GridSpec = {
  columns: number[]
  rows: number[]
  slots: TilingSlot[]
  miniGraphSlot: TilingSlot | null
}

function evenSlots(cols: number, rows: number, capacity: number): TilingSlot[] {
  const slots: TilingSlot[] = []
  let count = 0
  for (let row = 1; row <= rows && count < capacity; row += 1) {
    for (let col = 1; col <= cols && count < capacity; col += 1) {
      slots.push({ col, row, colSpan: 1, rowSpan: 1 })
      count += 1
    }
  }
  return slots
}

function mobileGrid(n: number): GridSpec {
  return {
    columns: [1],
    rows: Array(n).fill(1),
    slots: Array.from({ length: n }, (_, i) => ({
      col: 1,
      row: i + 1,
      colSpan: 1,
      rowSpan: 1,
    })),
    miniGraphSlot: null,
  }
}

function naturalGrid(n: number, viewport: Viewport): GridSpec {
  if (viewport.width < MOBILE_BREAKPOINT) return mobileGrid(n)
  const isTablet = viewport.width < TABLET_BREAKPOINT
  const maxCols = isTablet ? 2 : 3

  if (n === 1) {
    return {
      columns: [1],
      rows: [1],
      slots: [{ col: 1, row: 1, colSpan: 1, rowSpan: 1 }],
      miniGraphSlot: null,
    }
  }
  if (n === 2) {
    return {
      columns: [1, 1],
      rows: [1],
      slots: [
        { col: 1, row: 1, colSpan: 1, rowSpan: 1 },
        { col: 2, row: 1, colSpan: 1, rowSpan: 1 },
      ],
      miniGraphSlot: null,
    }
  }
  if (n === 3) {
    return {
      columns: [GOLDEN_LEFT, GOLDEN_RIGHT],
      rows: [1, 1],
      slots: [
        { col: 1, row: 1, colSpan: 1, rowSpan: 2 },
        { col: 2, row: 1, colSpan: 1, rowSpan: 1 },
        { col: 2, row: 2, colSpan: 1, rowSpan: 1 },
      ],
      miniGraphSlot: null,
    }
  }
  if (n === 4) {
    return {
      columns: [1, 1],
      rows: [1, 1],
      slots: evenSlots(2, 2, 4),
      miniGraphSlot: null,
    }
  }
  if (n <= 6) {
    const cols = Math.min(maxCols, 3)
    const rows = Math.ceil(n / cols)
    return {
      columns: Array(cols).fill(1),
      rows: Array(rows).fill(1),
      slots: evenSlots(cols, rows, n),
      miniGraphSlot: null,
    }
  }
  // n in 7..9
  const cols = Math.min(maxCols, 3)
  if (cols === 3) {
    const slots = evenSlots(3, 3, n)
    const miniGraphSlot: TilingSlot | null =
      n === 8 ? { col: 3, row: 3, colSpan: 1, rowSpan: 1 } : null
    return { columns: [1, 1, 1], rows: [1, 1, 1], slots, miniGraphSlot }
  }
  const rows = Math.ceil(n / 2)
  return {
    columns: [1, 1],
    rows: Array(rows).fill(1),
    slots: evenSlots(2, rows, n),
    miniGraphSlot: null,
  }
}

function wallSpec(): { columns: number[]; rows: number[]; slots: TilingSlot[] } {
  return {
    columns: [1, 1],
    rows: [0.4, 0.6],
    slots: [
      { col: 1, row: 1, colSpan: 1, rowSpan: 1 },
      { col: 2, row: 1, colSpan: 1, rowSpan: 1 },
    ],
  }
}

function isCramped(grid: GridSpec, viewport: Viewport): boolean {
  if (grid.columns.length === 0 || grid.rows.length === 0) return false
  const colWidth = viewport.width / grid.columns.length
  const rowHeight = viewport.height / grid.rows.length
  return colWidth < MIN_TILE_W || rowHeight < MIN_TILE_H
}

function computeWeight(slot: TilingSlot, columns: number[], rows: number[]): number {
  const colSum = columns.reduce((acc, w) => acc + w, 0)
  const rowSum = rows.reduce((acc, h) => acc + h, 0)
  if (colSum === 0 || rowSum === 0) return 0
  let colSpan = 0
  for (let c = slot.col - 1; c < slot.col - 1 + slot.colSpan; c += 1) {
    colSpan += columns[c] ?? 0
  }
  let rowSpan = 0
  for (let r = slot.row - 1; r < slot.row - 1 + slot.rowSpan; r += 1) {
    rowSpan += rows[r] ?? 0
  }
  return (colSpan * rowSpan) / (colSum * rowSum)
}

function buildTiles(
  sessions: TentacleSession[],
  spec: { columns: number[]; rows: number[]; slots: TilingSlot[] }
): TilingTile[] {
  const tiles: TilingTile[] = []
  for (let i = 0; i < sessions.length; i += 1) {
    const session = sessions[i]
    const slot = spec.slots[i]
    if (!session || !slot) continue
    tiles.push({
      kind: "terminal",
      session,
      col: slot.col,
      row: slot.row,
      colSpan: slot.colSpan,
      rowSpan: slot.rowSpan,
      weight: computeWeight(slot, spec.columns, spec.rows),
    })
  }
  return tiles
}

export function selectTilingLayout(input: Input): TilingLayout {
  const alive = input.sessions.filter((s) => s.alive)

  if (alive.length === 0) {
    return {
      tiles: [],
      cards: [],
      miniGraphSlot: null,
      columns: [],
      rows: [],
      hasMore: false,
    }
  }

  const ranked = sortByPriority(alive, input.focusedId, input.runtimeStates)
  const hasMore = ranked.length > HARD_CAP
  const capped = ranked.slice(0, HARD_CAP)
  const isMobile = input.viewport.width < MOBILE_BREAKPOINT

  if (isMobile) {
    const grid = mobileGrid(capped.length)
    return {
      tiles: buildTiles(capped, grid),
      cards: [],
      miniGraphSlot: null,
      columns: grid.columns,
      rows: grid.rows,
      hasMore,
    }
  }

  let useWall = capped.length >= WALL_THRESHOLD
  if (!useWall && capped.length >= 3) {
    const probe = naturalGrid(capped.length, input.viewport)
    if (isCramped(probe, input.viewport)) useWall = true
  }

  if (useWall) {
    const wall = wallSpec()
    const largeCount = Math.min(capped.length, 2)
    const tiles = buildTiles(capped.slice(0, largeCount), wall)
    const cards: TilingCard[] = capped.slice(largeCount).map((session) => ({
      kind: "card",
      session,
    }))
    return {
      tiles,
      cards,
      miniGraphSlot: null,
      columns: wall.columns,
      rows: wall.rows,
      hasMore,
    }
  }

  const grid = naturalGrid(capped.length, input.viewport)
  return {
    tiles: buildTiles(capped, grid),
    cards: [],
    miniGraphSlot: grid.miniGraphSlot,
    columns: grid.columns,
    rows: grid.rows,
    hasMore,
  }
}
