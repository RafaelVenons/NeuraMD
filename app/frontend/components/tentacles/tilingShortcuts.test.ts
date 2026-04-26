import { describe, it, expect } from "vitest"

import {
  isEditableShortcutTarget,
  resolveTilingShortcut,
  selectNextTileId,
  selectPreviousTileId,
  selectTileByIndex,
} from "~/components/tentacles/tilingShortcuts"

const ids = ["a", "b", "c", "d"]

describe("selectTileByIndex", () => {
  it("returns the tile id for a valid 1-based index", () => {
    expect(selectTileByIndex(ids, 1)).toBe("a")
    expect(selectTileByIndex(ids, 4)).toBe("d")
  })

  it("returns null when index is out of range", () => {
    expect(selectTileByIndex(ids, 0)).toBeNull()
    expect(selectTileByIndex(ids, 5)).toBeNull()
    expect(selectTileByIndex([], 1)).toBeNull()
  })
})

describe("selectNextTileId", () => {
  it("returns the next id, wrapping at the end", () => {
    expect(selectNextTileId(ids, "a")).toBe("b")
    expect(selectNextTileId(ids, "c")).toBe("d")
    expect(selectNextTileId(ids, "d")).toBe("a")
  })

  it("returns the first id when current is null or unknown", () => {
    expect(selectNextTileId(ids, null)).toBe("a")
    expect(selectNextTileId(ids, "z")).toBe("a")
  })

  it("returns null when there are no tiles", () => {
    expect(selectNextTileId([], "a")).toBeNull()
  })
})

describe("selectPreviousTileId", () => {
  it("returns the previous id, wrapping at the start", () => {
    expect(selectPreviousTileId(ids, "b")).toBe("a")
    expect(selectPreviousTileId(ids, "d")).toBe("c")
    expect(selectPreviousTileId(ids, "a")).toBe("d")
  })

  it("returns the last id when current is null or unknown", () => {
    expect(selectPreviousTileId(ids, null)).toBe("d")
    expect(selectPreviousTileId(ids, "z")).toBe("d")
  })

  it("returns null when there are no tiles", () => {
    expect(selectPreviousTileId([], "a")).toBeNull()
  })
})

function altKey(key: string, opts: Partial<KeyboardEvent> = {}): KeyboardEvent {
  return new KeyboardEvent("keydown", { key, altKey: true, ...opts })
}

describe("resolveTilingShortcut", () => {
  it("ignores keydowns without Alt", () => {
    const event = new KeyboardEvent("keydown", { key: "1", altKey: false })
    expect(resolveTilingShortcut(event)).toBeNull()
  })

  it("ignores keydowns when meta or ctrl modifier is also pressed", () => {
    expect(resolveTilingShortcut(altKey("1", { ctrlKey: true }))).toBeNull()
    expect(resolveTilingShortcut(altKey("1", { metaKey: true }))).toBeNull()
  })

  it("resolves Alt+1..9 to focusIndex", () => {
    expect(resolveTilingShortcut(altKey("1"))).toEqual({ kind: "focusIndex", index: 1 })
    expect(resolveTilingShortcut(altKey("9"))).toEqual({ kind: "focusIndex", index: 9 })
  })

  it("ignores Alt+0 and Alt+other digits beyond 9", () => {
    expect(resolveTilingShortcut(altKey("0"))).toBeNull()
  })

  it("resolves Alt+j and Alt+J to next", () => {
    expect(resolveTilingShortcut(altKey("j"))).toEqual({ kind: "next" })
    expect(resolveTilingShortcut(altKey("J"))).toEqual({ kind: "next" })
  })

  it("resolves Alt+k and Alt+K to previous", () => {
    expect(resolveTilingShortcut(altKey("k"))).toEqual({ kind: "previous" })
    expect(resolveTilingShortcut(altKey("K"))).toEqual({ kind: "previous" })
  })

  it("resolves Alt+m to soloToggle", () => {
    expect(resolveTilingShortcut(altKey("m"))).toEqual({ kind: "soloToggle" })
  })

  it("resolves Alt+g to focusGraph", () => {
    expect(resolveTilingShortcut(altKey("g"))).toEqual({ kind: "focusGraph" })
  })

  it("returns null for unrecognised Alt+key combinations", () => {
    expect(resolveTilingShortcut(altKey("q"))).toBeNull()
    expect(resolveTilingShortcut(altKey("Tab"))).toBeNull()
  })
})

describe("isEditableShortcutTarget", () => {
  it("returns false for null and non-element targets", () => {
    expect(isEditableShortcutTarget(null)).toBe(false)
    expect(isEditableShortcutTarget(document)).toBe(false)
  })

  it("returns false for non-editable elements like buttons or spans", () => {
    const button = document.createElement("button")
    document.body.appendChild(button)
    expect(isEditableShortcutTarget(button)).toBe(false)

    const span = document.createElement("span")
    document.body.appendChild(span)
    expect(isEditableShortcutTarget(span)).toBe(false)
  })

  it("returns true for input, textarea and select", () => {
    for (const tag of ["input", "textarea", "select"] as const) {
      const el = document.createElement(tag)
      document.body.appendChild(el)
      expect(isEditableShortcutTarget(el)).toBe(true)
    }
  })

  it("returns true for elements inside a contenteditable region", () => {
    const editor = document.createElement("div")
    editor.setAttribute("contenteditable", "true")
    const child = document.createElement("p")
    editor.appendChild(child)
    document.body.appendChild(editor)
    expect(isEditableShortcutTarget(editor)).toBe(true)
    expect(isEditableShortcutTarget(child)).toBe(true)
  })

  it("returns true for elements inside an xterm canvas", () => {
    const term = document.createElement("div")
    term.className = "xterm"
    const helpers = document.createElement("div")
    helpers.className = "xterm-helpers"
    const helperTextarea = document.createElement("textarea")
    helperTextarea.className = "xterm-helper-textarea"
    helpers.appendChild(helperTextarea)
    term.appendChild(helpers)
    document.body.appendChild(term)
    expect(isEditableShortcutTarget(term)).toBe(true)
    expect(isEditableShortcutTarget(helpers)).toBe(true)
    expect(isEditableShortcutTarget(helperTextarea)).toBe(true)
  })
})
