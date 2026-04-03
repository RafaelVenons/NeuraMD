import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["viewport", "layer", "edgesSvg", "zoomLabel"]
  static values = {
    documentId: String,
    updateUrl: String,
    nodesUrl: String,
    edgesUrl: String,
    bulkUrl: String,
    viewport: Object,
    initialNodes: Array,
    initialEdges: Array
  }

  connect() {
    this._panX = this.viewportValue.x || 0
    this._panY = this.viewportValue.y || 0
    this._zoom = this.viewportValue.zoom || 1.0
    this._tool = "select"
    this._nodes = new Map()
    this._edges = new Map()
    this._selected = new Set()
    this._dragging = null
    this._panning = false
    this._edgeStart = null
    this._dirty = new Set()
    this._saveTimer = null

    this._applyTransform()
    this._renderInitialNodes()
    this._renderInitialEdges()
    this._bindKeyboard()
  }

  disconnect() {
    if (this._saveTimer) clearTimeout(this._saveTimer)
    document.removeEventListener("keydown", this._keyHandler)
  }

  // ── Tool communication (from canvas-toolbar dispatch) ────────────
  setTool(event) {
    this._tool = event.detail?.tool || "select"
    this.viewportTarget.style.cursor = this._tool === "pan" ? "grab" : "default"
  }

  // ── Pan / Zoom ───────────────────────────────────────────────────
  onWheel(event) {
    event.preventDefault()
    const delta = event.deltaY > 0 ? 0.9 : 1.1
    const newZoom = Math.min(5, Math.max(0.1, this._zoom * delta))

    // Zoom toward cursor position
    const rect = this.viewportTarget.getBoundingClientRect()
    const cx = event.clientX - rect.left
    const cy = event.clientY - rect.top

    this._panX = cx - (cx - this._panX) * (newZoom / this._zoom)
    this._panY = cy - (cy - this._panY) * (newZoom / this._zoom)
    this._zoom = newZoom

    this._applyTransform()
    this._scheduleSave()
  }

  onPointerDown(event) {
    if (event.target.closest(".cv-node")) return
    if (this._tool === "pan" || event.button === 1) {
      this._panning = true
      this._panStart = { x: event.clientX - this._panX, y: event.clientY - this._panY }
      this.viewportTarget.classList.add("cv-viewport--panning")
      this.viewportTarget.setPointerCapture(event.pointerId)
      event.preventDefault()
    } else if (this._tool === "select") {
      this._deselectAll()
    } else if (this._tool === "text" || this._tool === "note") {
      this._createNodeAtCursor(event)
    }
  }

  onPointerMove(event) {
    if (this._panning) {
      this._panX = event.clientX - this._panStart.x
      this._panY = event.clientY - this._panStart.y
      this._applyTransform()
    } else if (this._dragging) {
      const rect = this.viewportTarget.getBoundingClientRect()
      const cx = (event.clientX - rect.left - this._panX) / this._zoom
      const cy = (event.clientY - rect.top - this._panY) / this._zoom
      const node = this._dragging
      node.x = cx - node.offsetX
      node.y = cy - node.offsetY
      node.el.style.left = `${node.x}px`
      node.el.style.top = `${node.y}px`
      this._updateEdges()
    }
  }

  onPointerUp(event) {
    if (this._panning) {
      this._panning = false
      this.viewportTarget.classList.remove("cv-viewport--panning")
      this.viewportTarget.releasePointerCapture(event.pointerId)
      this._scheduleSave()
    } else if (this._dragging) {
      this._dirty.add(this._dragging.id)
      this._dragging = null
      this._scheduleSave()
    }
  }

  zoomIn() {
    this._zoom = Math.min(5, this._zoom * 1.2)
    this._applyTransform()
    this._scheduleSave()
  }

  zoomOut() {
    this._zoom = Math.max(0.1, this._zoom / 1.2)
    this._applyTransform()
    this._scheduleSave()
  }

  fitAll() {
    if (this._nodes.size === 0) return
    let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity
    for (const n of this._nodes.values()) {
      minX = Math.min(minX, n.x)
      minY = Math.min(minY, n.y)
      maxX = Math.max(maxX, n.x + n.width)
      maxY = Math.max(maxY, n.y + n.height)
    }
    const vw = this.viewportTarget.clientWidth
    const vh = this.viewportTarget.clientHeight
    const padding = 40
    const scaleX = (vw - padding * 2) / (maxX - minX || 1)
    const scaleY = (vh - padding * 2) / (maxY - minY || 1)
    this._zoom = Math.min(2, Math.max(0.1, Math.min(scaleX, scaleY)))
    this._panX = padding - minX * this._zoom
    this._panY = padding - minY * this._zoom
    this._applyTransform()
    this._scheduleSave()
  }

  // ── Selection ────────────────────────────────────────────────────
  deleteSelected() {
    for (const id of this._selected) {
      const node = this._nodes.get(id)
      if (node) {
        this._deleteNode(id)
      } else {
        // It might be an edge
        const edge = this._edges.get(id)
        if (edge) this._deleteEdge(id)
      }
    }
    this._selected.clear()
  }

  // ── Private: Transform ───────────────────────────────────────────
  _applyTransform() {
    this.layerTarget.style.transform = `translate(${this._panX}px, ${this._panY}px) scale(${this._zoom})`
    this.zoomLabelTarget.textContent = `${Math.round(this._zoom * 100)}%`
  }

  // ── Private: Node rendering ──────────────────────────────────────
  _renderInitialNodes() {
    for (const data of this.initialNodesValue) {
      this._addNodeElement(data)
    }
  }

  _addNodeElement(data) {
    const div = document.createElement("div")
    div.className = `cv-node cv-node--${data.node_type}`
    div.style.left = `${data.x}px`
    div.style.top = `${data.y}px`
    div.style.width = `${data.width}px`
    div.style.height = `${data.height}px`
    div.style.zIndex = data.z_index || 0
    div.dataset.nodeId = data.id

    if (data.node_type === "note") {
      div.innerHTML = `<div class="cv-node__title">${this._esc(data.title || "")}</div>
                       <div class="cv-node__excerpt">${this._esc(data.excerpt || "")}</div>`
      div.addEventListener("dblclick", () => { window.location.href = `/notes/${data.slug}` })
    } else if (data.node_type === "text") {
      const textEl = document.createElement("div")
      textEl.className = "cv-node__text"
      textEl.contentEditable = "true"
      textEl.textContent = data.data?.text || ""
      textEl.addEventListener("blur", () => this._updateNodeData(data.id, { text: textEl.textContent }))
      div.appendChild(textEl)
    } else if (data.node_type === "image") {
      div.innerHTML = `<img class="cv-node__image" src="${this._esc(data.data?.url || "")}" alt="">`
    } else if (data.node_type === "link") {
      div.innerHTML = `<div class="cv-node__url">${this._esc(data.data?.url || "")}</div>`
    }

    // Resize handle
    const handle = document.createElement("div")
    handle.className = "cv-node__resize"
    handle.addEventListener("pointerdown", (e) => this._onResizeStart(e, data.id))
    div.appendChild(handle)

    // Node interaction (selection handled in pointerdown)
    div.addEventListener("pointerdown", (e) => this._onNodePointerDown(e, data.id))

    this.layerTarget.appendChild(div)

    this._nodes.set(data.id, {
      id: data.id,
      el: div,
      x: data.x,
      y: data.y,
      width: data.width,
      height: data.height,
      node_type: data.node_type,
      note_id: data.note_id,
      data: data.data || {}
    })
  }

  _onNodePointerDown(event, nodeId) {
    if (event.target.closest(".cv-node__resize")) return
    if (event.target.closest("[contenteditable]")) return
    if (this._tool === "edge") {
      this._handleEdgeTool(nodeId)
      return
    }

    event.stopPropagation()
    event.preventDefault()
    const node = this._nodes.get(nodeId)
    if (!node) return

    const rect = this.viewportTarget.getBoundingClientRect()
    const cx = (event.clientX - rect.left - this._panX) / this._zoom
    const cy = (event.clientY - rect.top - this._panY) / this._zoom

    // Select the node immediately
    if (event.shiftKey) {
      this._toggleSelect(nodeId)
    } else if (!this._selected.has(nodeId)) {
      this._deselectAll()
      this._selectNode(nodeId)
    }

    this._dragging = {
      id: nodeId,
      el: node.el,
      x: node.x,
      y: node.y,
      offsetX: cx - node.x,
      offsetY: cy - node.y
    }

    // Capture on viewport for smooth dragging
    this.viewportTarget.setPointerCapture(event.pointerId)
  }

  _selectNode(id) {
    this._selected.add(id)
    const node = this._nodes.get(id)
    if (node) node.el.classList.add("cv-node--selected")
  }

  _toggleSelect(id) {
    if (this._selected.has(id)) {
      this._selected.delete(id)
      const node = this._nodes.get(id)
      if (node) node.el.classList.remove("cv-node--selected")
    } else {
      this._selectNode(id)
    }
  }

  _deselectAll() {
    for (const id of this._selected) {
      const node = this._nodes.get(id)
      if (node) node.el.classList.remove("cv-node--selected")
    }
    this._selected.clear()
  }

  // ── Private: Resize ──────────────────────────────────────────────
  _onResizeStart(event, nodeId) {
    event.stopPropagation()
    event.preventDefault()
    const node = this._nodes.get(nodeId)
    if (!node) return

    const startX = event.clientX
    const startY = event.clientY
    const startW = node.width
    const startH = node.height

    const onMove = (e) => {
      const dx = (e.clientX - startX) / this._zoom
      const dy = (e.clientY - startY) / this._zoom
      node.width = Math.max(120, startW + dx)
      node.height = Math.max(60, startH + dy)
      node.el.style.width = `${node.width}px`
      node.el.style.height = `${node.height}px`
      this._updateEdges()
    }

    const onUp = () => {
      document.removeEventListener("pointermove", onMove)
      document.removeEventListener("pointerup", onUp)
      this._dirty.add(nodeId)
      this._scheduleSave()
    }

    document.addEventListener("pointermove", onMove)
    document.addEventListener("pointerup", onUp)
  }

  // ── Private: Edge rendering ──────────────────────────────────────
  _renderInitialEdges() {
    for (const data of this.initialEdgesValue) {
      this._addEdgeElement(data)
    }
  }

  _addEdgeElement(data) {
    const path = document.createElementNS("http://www.w3.org/2000/svg", "path")
    path.classList.add("cv-edge-path")
    path.dataset.edgeId = data.id
    if (data.edge_type === "arrow") {
      path.setAttribute("marker-end", "url(#cv-arrowhead)")
    }
    if (data.edge_type === "dashed") {
      path.setAttribute("stroke-dasharray", "6 3")
    }
    path.style.pointerEvents = "stroke"
    path.addEventListener("click", (e) => {
      e.stopPropagation()
      this._deselectAll()
      this._selected.add(data.id)
      path.classList.add("cv-edge-path--selected")
    })

    this.edgesSvgTarget.appendChild(path)
    this._edges.set(data.id, {
      id: data.id,
      el: path,
      source_node_id: data.source_node_id,
      target_node_id: data.target_node_id,
      edge_type: data.edge_type
    })

    this._updateEdgePath(data.id)
  }

  _updateEdges() {
    for (const id of this._edges.keys()) {
      this._updateEdgePath(id)
    }
  }

  _updateEdgePath(edgeId) {
    const edge = this._edges.get(edgeId)
    if (!edge) return
    const src = this._nodes.get(edge.source_node_id)
    const tgt = this._nodes.get(edge.target_node_id)
    if (!src || !tgt) return

    const sx = src.x + src.width / 2
    const sy = src.y + src.height / 2
    const tx = tgt.x + tgt.width / 2
    const ty = tgt.y + tgt.height / 2

    // Quadratic Bezier with slight curve
    const mx = (sx + tx) / 2
    const my = (sy + ty) / 2
    const dx = tx - sx
    const dy = ty - sy
    const cx = mx - dy * 0.1
    const cy = my + dx * 0.1

    edge.el.setAttribute("d", `M ${sx} ${sy} Q ${cx} ${cy} ${tx} ${ty}`)
  }

  // ── Private: Edge tool ───────────────────────────────────────────
  _handleEdgeTool(nodeId) {
    if (!this._edgeStart) {
      this._edgeStart = nodeId
      const node = this._nodes.get(nodeId)
      if (node) node.el.classList.add("cv-node--selected")
    } else {
      if (this._edgeStart !== nodeId) {
        this._createEdge(this._edgeStart, nodeId)
      }
      const startNode = this._nodes.get(this._edgeStart)
      if (startNode) startNode.el.classList.remove("cv-node--selected")
      this._edgeStart = null
    }
  }

  async _createEdge(sourceId, targetId) {
    const response = await fetch(this.edgesUrlValue, {
      method: "POST",
      headers: this._jsonHeaders(),
      body: JSON.stringify({
        canvas_edge: { source_node_id: sourceId, target_node_id: targetId, edge_type: "arrow" }
      })
    })
    if (response.ok) {
      const data = await response.json()
      this._addEdgeElement(data)
    }
  }

  // ── Private: Node creation ───────────────────────────────────────
  async _createNodeAtCursor(event) {
    const rect = this.viewportTarget.getBoundingClientRect()
    const x = (event.clientX - rect.left - this._panX) / this._zoom
    const y = (event.clientY - rect.top - this._panY) / this._zoom

    const nodeData = {
      canvas_node: {
        node_type: this._tool === "note" ? "text" : "text",
        x: Math.round(x),
        y: Math.round(y),
        width: 240,
        height: 120,
        data: JSON.stringify({ text: "" })
      }
    }

    const response = await fetch(this.nodesUrlValue, {
      method: "POST",
      headers: this._jsonHeaders(),
      body: JSON.stringify(nodeData)
    })

    if (response.ok) {
      const data = await response.json()
      this._addNodeElement(data)
    }
  }

  // ── Private: Delete ──────────────────────────────────────────────
  async _deleteNode(nodeId) {
    const node = this._nodes.get(nodeId)
    if (!node) return

    await fetch(`${this.nodesUrlValue}/${nodeId}`, {
      method: "DELETE",
      headers: this._jsonHeaders()
    })

    node.el.remove()
    this._nodes.delete(nodeId)

    // Remove connected edges
    for (const [eid, edge] of this._edges) {
      if (edge.source_node_id === nodeId || edge.target_node_id === nodeId) {
        edge.el.remove()
        this._edges.delete(eid)
      }
    }
  }

  async _deleteEdge(edgeId) {
    const edge = this._edges.get(edgeId)
    if (!edge) return

    await fetch(`${this.edgesUrlValue}/${edgeId}`, {
      method: "DELETE",
      headers: this._jsonHeaders()
    })

    edge.el.remove()
    this._edges.delete(edgeId)
  }

  // ── Private: Node data update ────────────────────────────────────
  async _updateNodeData(nodeId, newData) {
    const node = this._nodes.get(nodeId)
    if (!node) return
    Object.assign(node.data, newData)

    await fetch(`${this.nodesUrlValue}/${nodeId}`, {
      method: "PATCH",
      headers: this._jsonHeaders(),
      body: JSON.stringify({ canvas_node: { data: JSON.stringify(node.data) } })
    })
  }

  // ── Private: Auto-save ───────────────────────────────────────────
  _scheduleSave() {
    if (this._saveTimer) clearTimeout(this._saveTimer)
    this._saveTimer = setTimeout(() => this._save(), 800)
  }

  async _save() {
    // Save viewport
    fetch(this.updateUrlValue, {
      method: "PATCH",
      headers: this._jsonHeaders(),
      body: JSON.stringify({
        canvas_document: {
          viewport: JSON.stringify({ x: this._panX, y: this._panY, zoom: this._zoom })
        }
      })
    })

    // Bulk update dirty nodes
    if (this._dirty.size > 0) {
      const nodes = []
      for (const id of this._dirty) {
        const node = this._nodes.get(id)
        if (node) {
          nodes.push({ id, x: node.x, y: node.y, width: node.width, height: node.height })
        }
      }
      this._dirty.clear()

      if (nodes.length > 0) {
        fetch(this.bulkUrlValue, {
          method: "PATCH",
          headers: this._jsonHeaders(),
          body: JSON.stringify({ nodes })
        })
      }
    }
  }

  // ── Private: Keyboard ────────────────────────────────────────────
  _bindKeyboard() {
    this._keyHandler = (e) => {
      if (e.target.closest("[contenteditable]") || e.target.closest("input") || e.target.closest("textarea")) return

      if (e.key === "Delete" || e.key === "Backspace") {
        this.deleteSelected()
      } else if (e.key === "v" || e.key === "V") {
        this._setToolFromKey("select")
      } else if (e.key === "h" || e.key === "H") {
        this._setToolFromKey("pan")
      } else if (e.key === "t" || e.key === "T") {
        this._setToolFromKey("text")
      } else if (e.key === "n" || e.key === "N") {
        this._setToolFromKey("note")
      } else if (e.key === "e" || e.key === "E") {
        this._setToolFromKey("edge")
      } else if (e.key === "0" && (e.ctrlKey || e.metaKey)) {
        e.preventDefault()
        this._zoom = 1.0
        this._panX = 0
        this._panY = 0
        this._applyTransform()
        this._scheduleSave()
      } else if (e.key === "a" && (e.ctrlKey || e.metaKey)) {
        e.preventDefault()
        for (const id of this._nodes.keys()) {
          this._selectNode(id)
        }
      }
    }
    document.addEventListener("keydown", this._keyHandler)
  }

  _setToolFromKey(tool) {
    this._tool = tool
    this.viewportTarget.style.cursor = tool === "pan" ? "grab" : "default"
    // Update toolbar buttons via dispatch
    this.dispatch("toolChanged", { detail: { tool } })
  }

  // ── Helpers ──────────────────────────────────────────────────────
  _jsonHeaders() {
    return {
      "Content-Type": "application/json",
      "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content || "",
      Accept: "application/json"
    }
  }

  _esc(str) {
    return (str || "").toString()
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
  }
}
