import { Controller } from "@hotwired/stimulus"

const ROLE_COLORS = {
  target_is_parent: "#8b5cf6",
  target_is_child: "#34d399",
  same_level: "#f59e0b",
  reference: "#3b82f6"
}

export default class extends Controller {
  static targets = [
    "canvas",
    "empty",
    "error",
    "legend",
    "meta",
    "nodeFilter",
    "focusFilter",
    "tagFilter",
    "depthFilter",
    "roleParent",
    "roleChild",
    "roleSibling"
  ]

  static values = { dataUrl: String }

  connect() {
    this._graph = { nodes: [], edges: [], meta: {} }
    this._resizeObserver = new ResizeObserver(() => this.render())
    this._resizeObserver.observe(this.canvasTarget)
    this.load()
  }

  disconnect() {
    this._resizeObserver?.disconnect()
  }

  async load() {
    this.errorTarget.classList.add("hidden")
    this.emptyTarget.classList.add("hidden")
    this.metaTarget.textContent = "Carregando grafo..."

    try {
      const response = await fetch(this.dataUrlValue, {
        headers: { Accept: "application/json" }
      })
      const payload = await response.json()

      if (!response.ok) throw new Error(payload.error || "Nao foi possivel carregar o grafo.")

      this._graph = payload
      this._populateFilters()
      this.render()
    } catch (error) {
      this.canvasTarget.innerHTML = ""
      this.metaTarget.textContent = ""
      this.errorTarget.textContent = error.message
      this.errorTarget.classList.remove("hidden")
    }
  }

  render() {
    const { nodes, edges, meta } = this._visibleGraph()
    this.metaTarget.textContent = `${nodes.length} notas · ${edges.length} links`

    if (nodes.length === 0) {
      this.canvasTarget.innerHTML = ""
      this.emptyTarget.classList.remove("hidden")
      this._renderLegend([])
      return
    }

    this.emptyTarget.classList.add("hidden")
    this._renderLegend(edges)

    const width = Math.max(this.canvasTarget.clientWidth || 0, 640)
    const height = Math.max(this.canvasTarget.clientHeight || 0, 520)
    const layout = this._layout(nodes, width, height)
    const positions = new Map(layout.map((node) => [node.id, node]))

    this.canvasTarget.innerHTML = `
      <svg viewBox="0 0 ${width} ${height}" class="graph-canvas-svg" role="img" aria-label="Grafo de notas">
        <g class="graph-canvas__edges">
          ${edges.map((edge) => this._edgeSvg(edge, positions)).join("")}
        </g>
        <g class="graph-canvas__nodes">
          ${layout.map((node) => this._nodeSvg(node)).join("")}
        </g>
      </svg>
    `
  }

  applyFilters() {
    this.render()
  }

  openNode(event) {
    const group = event.target.closest("[data-node-slug]")
    if (!group) return

    const href = `/notes/${group.dataset.nodeSlug}`
    if (window.Turbo?.visit) {
      window.Turbo.visit(href)
    } else {
      window.location.href = href
    }
  }

  _populateFilters() {
    const tags = [...new Map(
      this._graph.edges.flatMap((edge) => edge.tags || []).map((tag) => [tag.id, tag])
    ).values()].sort((a, b) => a.name.localeCompare(b.name))

    const notes = [...this._graph.nodes].sort((a, b) => a.title.localeCompare(b.title))
    const currentFocus = this.hasFocusFilterTarget ? this.focusFilterTarget.value : ""

    this.tagFilterTarget.innerHTML = [
      `<option value="">Todas as tags</option>`,
      ...tags.map((tag) => `<option value="${tag.id}">${this._escapeHtml(tag.name)}</option>`)
    ].join("")

    this.focusFilterTarget.innerHTML = [
      `<option value="">Sem foco</option>`,
      ...notes.map((note) => `<option value="${note.id}">${this._escapeHtml(note.title)}</option>`)
    ].join("")
    this.focusFilterTarget.value = currentFocus
  }

  _visibleGraph() {
    const query = this.nodeFilterTarget.value.trim().toLowerCase()
    const tagId = this.tagFilterTarget.value
    const focusId = this.focusFilterTarget.value
    const maxDepth = this.depthFilterTarget.value
    const enabledRoles = this._enabledRoles()

    let nodes = [...this._graph.nodes]
    let edges = this._graph.edges.filter((edge) => enabledRoles.has(edge.hier_role || "reference"))

    if (tagId) {
      edges = edges.filter((edge) => (edge.tags || []).some((tag) => tag.id === tagId))
    }

    if (focusId && maxDepth !== "all") {
      const allowedIds = this._nodesWithinDepth(focusId, edges, Number(maxDepth))
      nodes = nodes.filter((node) => allowedIds.has(node.id))
      edges = edges.filter((edge) => allowedIds.has(edge.source) && allowedIds.has(edge.target))
    }

    if (query) {
      const matchedIds = new Set(
        nodes.filter((node) => node.title.toLowerCase().includes(query)).map((node) => node.id)
      )
      nodes = nodes.filter((node) => matchedIds.has(node.id))
      edges = edges.filter((edge) => matchedIds.has(edge.source) && matchedIds.has(edge.target))
    }

    const visibleIds = new Set(nodes.map((node) => node.id))
    edges = edges.filter((edge) => visibleIds.has(edge.source) && visibleIds.has(edge.target))

    const degrees = new Map(nodes.map((node) => [node.id, 0]))
    edges.forEach((edge) => {
      degrees.set(edge.source, (degrees.get(edge.source) || 0) + 1)
      degrees.set(edge.target, (degrees.get(edge.target) || 0) + 1)
    })

    return {
      meta: this._graph.meta,
      nodes: nodes.map((node) => ({ ...node, visible_degree: degrees.get(node.id) || 0 })),
      edges
    }
  }

  _nodesWithinDepth(rootId, edges, maxDepth) {
    const adjacency = new Map()

    edges.forEach((edge) => {
      if (!adjacency.has(edge.source)) adjacency.set(edge.source, new Set())
      if (!adjacency.has(edge.target)) adjacency.set(edge.target, new Set())
      adjacency.get(edge.source).add(edge.target)
      adjacency.get(edge.target).add(edge.source)
    })

    const visited = new Set([rootId])
    const queue = [{ id: rootId, depth: 0 }]

    while (queue.length > 0) {
      const current = queue.shift()
      if (current.depth >= maxDepth) continue

      ;(adjacency.get(current.id) || []).forEach((neighborId) => {
        if (visited.has(neighborId)) return
        visited.add(neighborId)
        queue.push({ id: neighborId, depth: current.depth + 1 })
      })
    }

    return visited
  }

  _enabledRoles() {
    const roles = new Set(["reference"])
    if (this.roleParentTarget.checked) roles.add("target_is_parent")
    if (this.roleChildTarget.checked) roles.add("target_is_child")
    if (this.roleSiblingTarget.checked) roles.add("same_level")
    return roles
  }

  _layout(nodes, width, height) {
    const cx = width / 2
    const cy = height / 2
    const ring = Math.max(Math.min(width, height) / 2 - 70, 140)
    const sorted = [...nodes].sort((a, b) => {
      if (b.visible_degree !== a.visible_degree) return b.visible_degree - a.visible_degree
      return a.title.localeCompare(b.title)
    })

    return sorted.map((node, index) => {
      const angle = (Math.PI * 2 * index) / Math.max(sorted.length, 1) - Math.PI / 2
      const orbit = ring - ((index % 3) * 28)
      return {
        ...node,
        x: cx + Math.cos(angle) * orbit,
        y: cy + Math.sin(angle) * orbit,
        radius: 12 + Math.min(node.visible_degree, 6) * 2,
        color: this._nodeColor(node)
      }
    })
  }

  _nodeColor(node) {
    const language = (node.detected_language || "").toLowerCase()
    if (language.startsWith("ja")) return "#f59e0b"
    if (language.startsWith("zh")) return "#ef4444"
    if (language.startsWith("ko")) return "#10b981"
    return "#60a5fa"
  }

  _edgeSvg(edge, positions) {
    const source = positions.get(edge.source)
    const target = positions.get(edge.target)
    if (!source || !target) return ""

    const color = edge.tags?.[0]?.color_hex || ROLE_COLORS[edge.hier_role] || ROLE_COLORS.reference
    const dashed = edge.hier_role === "same_level" ? `stroke-dasharray="7 5"` : ""

    return `
      <line x1="${source.x}" y1="${source.y}" x2="${target.x}" y2="${target.y}"
            stroke="${color}" stroke-width="2.2" stroke-linecap="round" opacity="0.8" ${dashed}></line>
    `
  }

  _nodeSvg(node) {
    const labelY = node.y + node.radius + 16

    return `
      <g class="graph-node" data-node-slug="${this._escapeHtml(node.slug)}" tabindex="0">
        <circle cx="${node.x}" cy="${node.y}" r="${node.radius}" fill="${node.color}"></circle>
        <circle cx="${node.x}" cy="${node.y}" r="${node.radius + 5}" fill="transparent" stroke="${node.color}" stroke-opacity="0.24"></circle>
        <text x="${node.x}" y="${labelY}" text-anchor="middle">${this._escapeHtml(this._truncate(node.title, 18))}</text>
      </g>
    `
  }

  _renderLegend(edges) {
    const tags = [...new Map(
      edges.flatMap((edge) => edge.tags || []).map((tag) => [tag.id, tag])
    ).values()]

    this.legendTarget.innerHTML = [
      this._legendChip("Father", ROLE_COLORS.target_is_parent),
      this._legendChip("Child", ROLE_COLORS.target_is_child),
      this._legendChip("Brother", ROLE_COLORS.same_level),
      this._legendChip("Ref", ROLE_COLORS.reference),
      ...tags.slice(0, 6).map((tag) => this._legendChip(tag.name, tag.color_hex || "#94a3b8"))
    ].join("")
  }

  _legendChip(label, color) {
    return `
      <span class="graph-legend__chip">
        <span class="graph-legend__dot" style="background:${color}"></span>
        ${this._escapeHtml(label)}
      </span>
    `
  }

  _truncate(value, maxLength) {
    return value.length > maxLength ? `${value.slice(0, maxLength - 1)}…` : value
  }

  _escapeHtml(value) {
    return (value || "")
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
  }
}
