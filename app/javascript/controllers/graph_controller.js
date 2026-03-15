import { Controller } from "@hotwired/stimulus"
import Sigma from "sigma"
import { createAppState } from "graph/app_state"
import { buildGraph } from "graph/graph_builder"
import { buildIndexes } from "graph/graph_indexes"
import { deriveInitialTagOrder, moveTag } from "graph/graph_tags"
import { computeDisplayState } from "graph/graph_filters"
import { animateNodePositions, applyLayout, assignNodePositions, captureNodePositions } from "graph/graph_layout"
import { animateCameraToNode } from "graph/graph_focus"
import { renderTooltip } from "graph/graph_tooltip"
import { renderTagList } from "graph/graph_sidebar"
import { createEdgeProgramClasses } from "graph/graph_custom_edge_program"
import { visitWithPageTransition } from "lib/page_transition"

export default class extends Controller {
  static targets = [
    "meta",
    "graphHost",
    "tooltipLayer",
    "empty",
    "error",
    "tagList",
    "filterMode",
    "topN",
    "topNAll",
    "focusDepth",
    "search"
  ]

  static values = {
    dataUrl: String,
    initialFocusedNodeId: Number,
    embeddedMode: Boolean
  }

  connect() {
    this.state = createAppState()
    window.__graphDebug = this
    this._boundResize = () => this.positionTooltip()
    this._resizeObserver = new ResizeObserver(() => {
      this.state.renderer?.refresh()
      this.positionTooltip()
    })
    this._resizeObserver.observe(this.graphHostTarget)
    window.addEventListener("resize", this._boundResize)
    this._boundTooltipClick = (event) => this.handleTooltipClick(event)
    this.tooltipLayerTarget.addEventListener("click", this._boundTooltipClick)
    if (this.hasTopNTarget && this.hasTopNAllTarget) this.topNTarget.disabled = this.topNAllTarget.checked
    this.load()
  }

  disconnect() {
    if (window.__graphDebug === this) delete window.__graphDebug
    window.removeEventListener("resize", this._boundResize)
    this._resizeObserver?.disconnect()
    this.tooltipLayerTarget.removeEventListener("click", this._boundTooltipClick)
    this.destroyRenderer()
  }

  async load() {
    this.errorTarget.classList.add("hidden")
    if (this.hasMetaTarget) this.metaTarget.textContent = "Carregando dataset..."

    try {
      const response = await fetch(this.dataUrlValue, {
        headers: { Accept: "application/json" }
      })
      const payload = await response.json()
      if (!response.ok) throw new Error(payload.error || "Falha ao carregar o grafo.")

      const { graph, dropped } = buildGraph(payload)
      dropped.forEach((entry) => console.warn("graphology dropped edge", entry))

      this.state.dataset = payload
      this.state.graph = graph
      this.state.indexes = buildIndexes(payload, graph)
      this.state.ui.activeTagsOrdered = deriveInitialTagOrder(payload)
      if (this.hasInitialFocusedNodeIdValue && graph.hasNode(this.initialFocusedNodeIdValue)) {
        this.state.ui.focusedNodeId = this.initialFocusedNodeIdValue
      }

      applyLayout(graph, this.state, { rebuild: true })
      this.mountRenderer()
      this.renderSidebar()
      this.applyDisplayState({ relayout: false, animateFocus: this.hasInitialFocusedNodeIdValue })
    } catch (error) {
      this.errorTarget.textContent = error.message
      this.errorTarget.classList.remove("hidden")
      if (this.hasMetaTarget) this.metaTarget.textContent = ""
    }
  }

  mountRenderer() {
    this.destroyRenderer()

    this.state.renderer = new Sigma(this.state.graph, this.graphHostTarget, {
      allowInvalidContainer: true,
      renderEdgeLabels: false,
      labelDensity: 0.08,
      labelSize: "fixed",
      defaultLabelSize: 14,
      labelRenderedSizeThreshold: 10,
      labelColor: { attribute: "labelColor" },
      defaultEdgeType: "line",
      defaultNodeType: "circle",
      hideLabelsOnMove: true,
      enableEdgeEvents: true,
      edgeProgramClasses: createEdgeProgramClasses(),
      nodeReducer: (nodeId, data) => ({ ...data, ...(this.state.display.nodes.get(nodeId) || {}) }),
      edgeReducer: (edgeId, data) => ({ ...data, ...(this.state.display.edges.get(edgeId) || {}) })
    })

    this.bindMouseLayerEvents()

    this.state.renderer.on("afterRender", () => this.positionTooltip())
  }

  destroyRenderer() {
    this.unbindMouseLayerEvents()
    this.state.renderer?.kill()
    this.state.renderer = null
    this.graphHostTarget.innerHTML = ""
    this.tooltipLayerTarget.innerHTML = ""
  }

  bindMouseLayerEvents() {
    const mouseLayer = this.state.renderer?.getCanvases?.().mouse
    if (!mouseLayer) return

    this._mouseLayer = mouseLayer
    this._boundGraphMouseMove = (event) => this.handleMouseLayerMove(event)
    this._boundGraphMouseLeave = () => this.handleMouseLayerLeave()
    this._boundGraphClick = (event) => this.handleMouseLayerClick(event)
    this._boundGraphDoubleClick = (event) => this.handleMouseLayerDoubleClick(event)

    mouseLayer.addEventListener("mousemove", this._boundGraphMouseMove)
    mouseLayer.addEventListener("mouseleave", this._boundGraphMouseLeave)
    mouseLayer.addEventListener("click", this._boundGraphClick)
    mouseLayer.addEventListener("dblclick", this._boundGraphDoubleClick)
  }

  unbindMouseLayerEvents() {
    if (!this._mouseLayer) return

    this._mouseLayer.removeEventListener("mousemove", this._boundGraphMouseMove)
    this._mouseLayer.removeEventListener("mouseleave", this._boundGraphMouseLeave)
    this._mouseLayer.removeEventListener("click", this._boundGraphClick)
    this._mouseLayer.removeEventListener("dblclick", this._boundGraphDoubleClick)

    this._mouseLayer = null
    this._boundGraphMouseMove = null
    this._boundGraphMouseLeave = null
    this._boundGraphClick = null
    this._boundGraphDoubleClick = null
  }

  handleMouseLayerMove(event) {
    const nodeId = this.nodeAtPointer(event)
    if (nodeId === this.state.ui.hoveredNodeId) {
      this.positionTooltip()
      return
    }

    this.state.ui.hoveredNodeId = nodeId

    if (!this.state.ui.pinnedTooltipNodeId) this.applyDisplayState({ relayout: false, animateFocus: false })
    else this.positionTooltip()
  }

  handleMouseLayerLeave() {
    this.state.ui.hoveredNodeId = null

    if (!this.state.ui.pinnedTooltipNodeId) this.applyDisplayState({ relayout: false, animateFocus: false })
    else this.positionTooltip()
  }

  handleMouseLayerClick(event) {
    const nodeId = this.nodeAtPointer(event)

    if (nodeId) {
      this.state.ui.hoveredNodeId = nodeId
      this.state.ui.focusedNodeId = nodeId
      this.state.ui.pinnedTooltipNodeId = nodeId
      this.applyDisplayState({ relayout: true, animateFocus: true })
      return
    }

    this.state.ui.hoveredNodeId = null
    this.state.ui.focusedNodeId = null
    this.state.ui.pinnedTooltipNodeId = null
    this.applyDisplayState({ relayout: true, animateFocus: false })
  }

  handleMouseLayerDoubleClick(event) {
    const nodeId = this.nodeAtPointer(event)
    if (!nodeId) return

    const slug = this.state.graph.getNodeAttribute(nodeId, "slug")
    this.visit(`/notes/${slug}`, { kind: "graph-to-note" })
  }

  handleTooltipClick(event) {
    const link = event.target.closest(".nm-graph-tooltip")
    if (!link) return

    event.preventDefault()
    this.visit(link.getAttribute("href"), { kind: "graph-to-note" })
  }

  nodeAtPointer(event) {
    if (!this.state.renderer || !this._mouseLayer) return null

    const rect = this._mouseLayer.getBoundingClientRect()
    const point = {
      x: event.clientX - rect.left,
      y: event.clientY - rect.top
    }
    const nodeId = this.state.renderer.getNodeAtPosition(point)

    if (nodeId) {
      const display = this.state.display.nodes.get(nodeId)
      return display?.hidden ? null : nodeId
    }

    return this.closestVisibleNodeToViewportPoint(point)
  }

  closestVisibleNodeToViewportPoint(point) {
    let bestNodeId = null
    let bestDistance = Infinity

    this.state.graph.forEachNode((nodeId) => {
      const display = this.state.display.nodes.get(nodeId)
      if (!display || display.hidden) return

      const node = this.state.renderer.getNodeDisplayData(nodeId)
      if (!node) return

      const viewport = this.state.renderer.graphToViewport({ x: node.x, y: node.y })
      const dx = viewport.x - point.x
      const dy = viewport.y - point.y
      const distance = Math.sqrt(dx * dx + dy * dy)
      const threshold = Math.max(14, (node.size || display.size || 7) * 2.2)

      if (distance <= threshold && distance < bestDistance) {
        bestNodeId = nodeId
        bestDistance = distance
      }
    })

    return bestNodeId
  }

  updateFilterMode() {
    this.state.ui.filterMode = this.filterModeTarget.value
    this.applyDisplayState({ relayout: false, animateFocus: false })
  }

  updateTopN() {
    if (this.topNAllTarget.checked) {
      this.state.ui.topN = null
    } else {
      const parsed = Number(this.topNTarget.value)
      this.state.ui.topN = Number.isFinite(parsed) && parsed > 0 ? Math.floor(parsed) : 1
      this.topNTarget.value = String(this.state.ui.topN)
    }
    this.renderSidebar()
    this.applyDisplayState({ relayout: false, animateFocus: false })
  }

  updateTopNMode() {
    const useAll = this.topNAllTarget.checked
    this.topNTarget.disabled = useAll
    if (useAll) this.state.ui.topN = null
    else if (this.state.ui.topN == null) this.state.ui.topN = Math.max(Number(this.topNTarget.value) || 3, 1)

    this.renderSidebar()
    this.applyDisplayState({ relayout: false, animateFocus: false })
  }

  updateDepth() {
    this.state.ui.focusDepth = Number(this.focusDepthTarget.value)
    this.applyDisplayState({ relayout: true, animateFocus: true })
  }

  updateSearch() {
    this.state.ui.searchQuery = this.searchTarget.value.trim().toLowerCase()
    this.applyDisplayState({ relayout: false, animateFocus: false })
  }

  toggleRole(event) {
    const role = event.target.value
    if (event.target.checked) this.state.ui.enabledRoles.add(role)
    else this.state.ui.enabledRoles.delete(role)
    this.applyDisplayState({ relayout: false, animateFocus: false })
  }

  resetFocus() {
    this.state.ui.focusedNodeId = null
    this.state.ui.pinnedTooltipNodeId = null
    this.applyDisplayState({ relayout: true, animateFocus: false })
  }

  renderSidebar() {
    if (!this.hasTagListTarget) return

    renderTagList(this.tagListTarget, this.state, this.state.indexes, (tagId, delta) => {
      this.state.ui.activeTagsOrdered = moveTag(this.state.ui.activeTagsOrdered, tagId, delta)
      this.renderSidebar()
      this.applyDisplayState({ relayout: false, animateFocus: false })
    })
  }

  applyDisplayState({ relayout, animateFocus }) {
    if (!this.state.graph || !this.state.renderer) return

    let targetPositions = null
    if (relayout) {
      const currentPositions = captureNodePositions(this.state.graph)
      targetPositions = applyLayout(this.state.graph, this.state, { rebuild: false })
      assignNodePositions(this.state.graph, currentPositions)
      animateNodePositions(this.state.graph, this.state.renderer, currentPositions, targetPositions, this.state)
    }

    this.state.display = computeDisplayState(this.state)
    const visibleNodeCount = [...this.state.display.nodes.values()].filter((node) => !node.hidden).length
    const visibleEdgeCount = [...this.state.display.edges.values()].filter((edge) => !edge.hidden).length

    if (this.hasMetaTarget && !this.embeddedModeValue) {
      this.metaTarget.textContent = `${visibleNodeCount} notas · ${visibleEdgeCount} links · WebGL ativo`
    }
    this.emptyTarget.classList.toggle("hidden", visibleNodeCount > 0)
    this.state.renderer.refresh()

    if (animateFocus && this.state.ui.focusedNodeId) animateCameraToNode(this.state.renderer, this.state)
    this.positionTooltip()
  }

  positionTooltip() {
    const nodeId = this.state.ui.pinnedTooltipNodeId || this.state.ui.hoveredNodeId
    if (!nodeId || !this.state.renderer || !this.state.graph.hasNode(nodeId)) {
      this.tooltipLayerTarget.innerHTML = ""
      return
    }

    const display = this.state.display.nodes.get(nodeId)
    if (!display || display.hidden) {
      this.tooltipLayerTarget.innerHTML = ""
      return
    }

    const node = this.state.graph.getNodeAttributes(nodeId)
    const projected = this.state.renderer.graphToViewport({
      x: node.x,
      y: node.y
    })
    const horizontalClass = projected.x > this.graphHostTarget.clientWidth - 360 ? "is-left" : "is-right"
    const verticalClass = projected.y > this.graphHostTarget.clientHeight - 240 ? "is-top" : "is-middle"

    this.tooltipLayerTarget.innerHTML = `
      <div class="nm-graph__tooltip-anchor ${horizontalClass} ${verticalClass}" style="left:${projected.x}px;top:${projected.y}px">
        ${renderTooltip(node, this.state)}
      </div>
    `
  }

  visit(path, options = {}) {
    visitWithPageTransition(path, options)
  }
}
