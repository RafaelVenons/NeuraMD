import { Controller } from "@hotwired/stimulus"
import Sigma from "sigma"
import { createAppState } from "graph/app_state"
import { buildGraph } from "graph/graph_builder"
import { createNodeProgramClasses } from "graph/graph_custom_node_program"
import { buildIndexes } from "graph/graph_indexes"
import { deriveInitialTagOrder, moveTag, moveTagRelative, moveTagToFront, moveTagsToFront } from "graph/graph_tags"
import { computeDisplayState } from "graph/graph_filters"
import { animateNodePositions, applyLayout, assignNodePositions, captureNodePositions } from "graph/graph_layout"
import { animateCameraToNode, cancelCameraAnimation } from "graph/graph_focus"
import { renderTooltip } from "graph/graph_tooltip"
import { renderTagList, renderNoteCollections } from "graph/graph_sidebar"
import { createEdgeProgramClasses } from "graph/graph_custom_edge_program"
import { calculateArrowHeadGeometry } from "graph/graph_custom_edge_program"
import { drawNodeLabelAbove } from "graph/graph_node_label_renderer"
import { submitFormWithPageTransition, visitWithPageTransition } from "lib/page_transition"

export default class extends Controller {
  static NODE_HOLD_MS = 160
  static NODE_CLICK_MOVE_TOLERANCE = 5
  static NODE_DRAG_MOVE_TOLERANCE = 4
  static NODE_DOUBLE_CLICK_GRACE_MS = 360

  static targets = [
    "meta",
    "graphHost",
    "tooltipLayer",
    "empty",
    "error",
    "tagList",
    "tagTitle",
    "tagSearch",
    "linklessList",
    "promiseList",
    "filterMode",
    "topN",
    "topNAll",
    "focusDepth",
    "search"
  ]

  static values = {
    dataUrl: String,
    initialFocusedNodeId: String,
    embeddedMode: Boolean
  }

  connect() {
    this.state = createAppState()
    this.state.ui.isEmbedded = this.embeddedModeValue
    window.__graphDebug = this
    this.dragState = null
    this.nodePressState = null
    this.recentClickState = null
    this.stagePanState = null
    this._boundResize = () => this.positionTooltip()
    this._resizeObserver = new ResizeObserver(() => {
      this.state.renderer?.refresh()
      this.positionTooltip()
    })
    this._resizeObserver.observe(this.graphHostTarget)
    window.addEventListener("resize", this._boundResize)
    this._boundTooltipClick = (event) => this.handleTooltipClick(event)
    this._edgeAnimationFrame = null
    this._edgeAnimationTick = 0
    this._lastEdgeAnimationAt = 0
    this.tooltipLayerTarget.addEventListener("click", this._boundTooltipClick)
    this._boundDropdownToggle = (event) => this.handleDropdownToggle(event)
    this.element.querySelectorAll(".nm-graph__dropdown").forEach((dropdown) => {
      dropdown.addEventListener("toggle", this._boundDropdownToggle)
    })
    if (this.hasTopNTarget && this.hasTopNAllTarget) this.topNTarget.disabled = this.topNAllTarget.checked
    this.load()
  }

  disconnect() {
    if (window.__graphDebug === this) delete window.__graphDebug
    window.removeEventListener("resize", this._boundResize)
    this._resizeObserver?.disconnect()
    this.tooltipLayerTarget.removeEventListener("click", this._boundTooltipClick)
    this.element.querySelectorAll(".nm-graph__dropdown").forEach((dropdown) => {
      dropdown.removeEventListener("toggle", this._boundDropdownToggle)
    })
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
        this.state.ui.pinnedTooltipNodeId = this.embeddedModeValue ? null : this.initialFocusedNodeIdValue
        this.state.ui.focusDepth = 2
        if (this.hasFocusDepthTarget) this.focusDepthTarget.value = "2"
      }

      applyLayout(graph, this.state, { rebuild: true })
      this.mountRenderer()
      this.renderSidebar()
      this.applyDisplayState({
        relayout: this.hasInitialFocusedNodeIdValue,
        animateFocus: this.hasInitialFocusedNodeIdValue
      })
    } catch (error) {
      this.errorTarget.textContent = error.message
      this.errorTarget.classList.remove("hidden")
      if (this.hasMetaTarget) this.metaTarget.textContent = ""
    }
  }

  mountRenderer() {
    this.destroyRenderer()
    const embeddedScale = this.embeddedModeValue ? 0.5 : 1

    this.state.renderer = new Sigma(this.state.graph, this.graphHostTarget, {
      allowInvalidContainer: true,
      renderEdgeLabels: false,
      labelDensity: 0.12,
      labelSize: "fixed",
      defaultLabelSize: 15,
      labelRenderedSizeThreshold: 7,
      labelFont: "\"Avenir Next\", \"Inter\", sans-serif",
      defaultDrawNodeLabel: drawNodeLabelAbove,
      labelColor: { attribute: "labelColor" },
      defaultEdgeType: "line",
      defaultNodeType: "circle",
      nodeProgramClasses: createNodeProgramClasses(drawNodeLabelAbove),
      hideLabelsOnMove: true,
      enableEdgeEvents: true,
      edgeProgramClasses: createEdgeProgramClasses(),
      nodeReducer: (nodeId, data) => {
        const reduced = { ...data, ...(this.state.display.nodes.get(nodeId) || {}) }
        if (embeddedScale === 1) return reduced

        return {
          ...reduced,
          size: (reduced.size || data.size || 1) * embeddedScale
        }
      },
      edgeReducer: (edgeId, data) => {
        const reduced = { ...data, ...(this.state.display.edges.get(edgeId) || {}) }
        if (embeddedScale === 1) return reduced

        return {
          ...reduced,
          size: (reduced.size || data.size || 1) * embeddedScale,
          srcPadding: (reduced.srcPadding ?? data.srcPadding ?? 0) * embeddedScale,
          dstPadding: (reduced.dstPadding ?? data.dstPadding ?? 0) * embeddedScale
        }
      }
    })

    this.bindMouseLayerEvents()
    this.startEdgeAnimationLoop()

    this.state.renderer.on("afterRender", () => this.positionTooltip())
  }

  destroyRenderer() {
    this.unbindMouseLayerEvents()
    this.clearNodePressState()
    this.cancelGraphMotion()
    this.state.renderer?.kill()
    this.state.renderer = null
    if (this._edgeAnimationFrame) cancelAnimationFrame(this._edgeAnimationFrame)
    this._edgeAnimationFrame = null
    this.graphHostTarget.innerHTML = ""
    this.tooltipLayerTarget.innerHTML = ""
  }

  startEdgeAnimationLoop() {
    if (this._edgeAnimationFrame) cancelAnimationFrame(this._edgeAnimationFrame)

    const tick = (now) => {
      if (!this.state.renderer) return

      if (document.visibilityState === "visible" && now - this._lastEdgeAnimationAt >= 41) {
        this._edgeAnimationTick += 1
        this._lastEdgeAnimationAt = now
        this.state.renderer.refresh()
      }

      this._edgeAnimationFrame = requestAnimationFrame(tick)
    }

    this._edgeAnimationFrame = requestAnimationFrame(tick)
  }

  bindMouseLayerEvents() {
    const mouseLayer = this.state.renderer?.getCanvases?.().mouse
    if (!mouseLayer) return

    this._mouseLayer = mouseLayer
    this._boundGraphMouseMove = (event) => this.handleMouseLayerMove(event)
    this._boundGraphMouseLeave = () => this.handleMouseLayerLeave()
    this._boundGraphMouseDown = (event) => this.handleMouseLayerDown(event)
    this._boundGraphClick = (event) => this.handleMouseLayerClick(event)
    this._boundGraphDoubleClick = (event) => this.handleMouseLayerDoubleClick(event)
    this._boundWindowMouseMove = (event) => this.handleWindowMouseMove(event)
    this._boundWindowMouseUp = (event) => this.handleWindowMouseUp(event)

    mouseLayer.addEventListener("mousedown", this._boundGraphMouseDown)
    mouseLayer.addEventListener("mousemove", this._boundGraphMouseMove)
    mouseLayer.addEventListener("mouseleave", this._boundGraphMouseLeave)
    mouseLayer.addEventListener("click", this._boundGraphClick)
    mouseLayer.addEventListener("dblclick", this._boundGraphDoubleClick)
    window.addEventListener("mousemove", this._boundWindowMouseMove)
    window.addEventListener("mouseup", this._boundWindowMouseUp)
  }

  unbindMouseLayerEvents() {
    if (!this._mouseLayer) return

    this._mouseLayer.removeEventListener("mousedown", this._boundGraphMouseDown)
    this._mouseLayer.removeEventListener("mousemove", this._boundGraphMouseMove)
    this._mouseLayer.removeEventListener("mouseleave", this._boundGraphMouseLeave)
    this._mouseLayer.removeEventListener("click", this._boundGraphClick)
    this._mouseLayer.removeEventListener("dblclick", this._boundGraphDoubleClick)
    window.removeEventListener("mousemove", this._boundWindowMouseMove)
    window.removeEventListener("mouseup", this._boundWindowMouseUp)

    this._mouseLayer = null
    this._boundGraphMouseDown = null
    this._boundGraphMouseMove = null
    this._boundGraphMouseLeave = null
    this._boundGraphClick = null
    this._boundGraphDoubleClick = null
    this._boundWindowMouseMove = null
    this._boundWindowMouseUp = null
  }

  handleMouseLayerMove(event) {
    if (this.dragState?.nodeId) {
      this.dragNodeToPointer(event)
      return
    }

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
    if (this.dragState?.nodeId) return

    this.state.ui.hoveredNodeId = null

    if (!this.state.ui.pinnedTooltipNodeId) this.applyDisplayState({ relayout: false, animateFocus: false })
    else this.positionTooltip()
  }

  handleMouseLayerDown(event) {
    if (event.button !== 0) return

    const nodeId = this.nodeAtPointer(event)
    if (!nodeId) {
      this.clearNodePressState()
      if (this.state.ui.focusedNodeId) {
        this.stagePanState = {
          pointerStart: this.pointerFromMouseEvent(event),
          released: false
        }
      }
      return
    }

    const pointer = this.pointerFromMouseEvent(event)
    const node = this.state.graph.getNodeAttributes(nodeId)
    this.cancelGraphMotion()
    this.nodePressState = {
      nodeId,
      downAt: Date.now(),
      pointerStart: pointer,
      latestPointer: pointer,
      startPosition: { x: node.x, y: node.y },
      holdTimer: window.setTimeout(() => {
        this.activateNodeDrag()
      }, this.constructor.NODE_HOLD_MS)
    }

    this.state.ui.hoveredNodeId = nodeId
    event.preventDefault()
    event.stopPropagation()
  }

  handleMouseLayerClick(event) {
    const nodeId = this.nodeAtPointer(event)
    if (nodeId) return

    this.state.ui.hoveredNodeId = null
    this.state.ui.focusedNodeId = null
    this.state.ui.pinnedTooltipNodeId = null
    this.applyDisplayState({ relayout: false, animateFocus: false })
  }

  handleMouseLayerDoubleClick(event) {
    const nodeId = this.resolveDoubleClickNodeId(event)
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

    const nodeId = this.exactNodeAtPointer(event)
    if (nodeId) return nodeId

    return this.closestVisibleNodeFromEvent(event)
  }

  exactNodeAtPointer(event) {
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

    return null
  }

  closestVisibleNodeFromEvent(event) {
    if (!this._mouseLayer) return null

    const rect = this._mouseLayer.getBoundingClientRect()
    return this.closestVisibleNodeToViewportPoint({
      x: event.clientX - rect.left,
      y: event.clientY - rect.top
    })
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
    this.applyDisplayState({ relayout: false, animateFocus: true })
  }

  updateSearch() {
    this.state.ui.searchQuery = this.searchTarget.value.trim().toLowerCase()
    this.applyDisplayState({ relayout: false, animateFocus: false })
  }

  openTagSearch() {
    if (!this.hasTagTitleTarget || !this.hasTagSearchTarget) return

    this.tagTitleTarget.hidden = true
    this.tagSearchTarget.hidden = false
    this.tagSearchTarget.value = this.state.ui.tagSearchQuery || ""
    this.tagSearchTarget.focus()
    this.tagSearchTarget.select()
  }

  closeTagSearch() {
    if (this.state.ui.tagSearchQuery?.trim()) return
    this.hideTagSearch()
  }

  handleTagSearchKeydown(event) {
    if (event.key !== "Escape") return

    event.preventDefault()
    this.state.ui.tagSearchQuery = ""
    this.tagSearchTarget.value = ""
    this.hideTagSearch()
    this.renderSidebar()
  }

  updateTagSearch() {
    this.state.ui.tagSearchQuery = this.tagSearchTarget.value
    this.renderSidebar()
  }

  hideTagSearch() {
    if (this.hasTagSearchTarget) this.tagSearchTarget.hidden = true
    if (this.hasTagTitleTarget) this.tagTitleTarget.hidden = false
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
    this.renderSidebar()
    this.applyDisplayState({ relayout: false, animateFocus: false })
  }

  renderSidebar() {
    if (this.hasTagListTarget) {
      renderTagList(this.tagListTarget, this.state, this.state.indexes, {
        onShift: (tagId, delta) => {
          this.applyTagOrderChange(() => {
            this.state.ui.activeTagsOrdered = moveTag(this.state.ui.activeTagsOrdered, tagId, delta)
          }, { focusTagId: tagId })
        },
        onReorder: (sourceTagId, targetTagId, placement) => {
          this.applyTagOrderChange(() => {
            this.state.ui.activeTagsOrdered = moveTagRelative(this.state.ui.activeTagsOrdered, sourceTagId, targetTagId, placement)
          }, { focusTagId: sourceTagId })
        },
        onToggle: async (tagId) => {
          await this.toggleFocusedNodeTag(tagId)
        }
      })
    }

    renderNoteCollections(
      {
        linklessList: this.hasLinklessListTarget ? this.linklessListTarget : null,
        promiseList: this.hasPromiseListTarget ? this.promiseListTarget : null
      },
      this.state,
      {
        onSelectNote: (noteId) => this.enterFocusMode(noteId),
        onCreatePromise: (title) => this.createNoteFromPromise(title)
      }
    )
  }

  handleDropdownToggle(event) {
    const openedDropdown = event.currentTarget
    if (!openedDropdown.open) return

    this.element.querySelectorAll(".nm-graph__dropdown").forEach((dropdown) => {
      if (dropdown !== openedDropdown) dropdown.open = false
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
      this.metaTarget.textContent = `${visibleNodeCount} notas · ${visibleEdgeCount} links`
    }
    this.emptyTarget.classList.toggle("hidden", visibleNodeCount > 0)
    this.state.renderer.refresh()

    if (animateFocus && this.state.ui.focusedNodeId) animateCameraToNode(this.state.renderer, this.state)
    this.positionTooltip()
  }

  positionTooltip() {
    if (this.embeddedModeValue) {
      this.tooltipLayerTarget.innerHTML = ""
      return
    }

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

  edgeArrowGeometry(edgeId) {
    if (!this.state.graph?.hasEdge(edgeId)) return null

    const sourceId = this.state.graph.source(edgeId)
    const targetId = this.state.graph.target(edgeId)
    const edge = this.state.graph.getEdgeAttributes(edgeId)
    const source = this.state.graph.getNodeAttributes(sourceId)
    const target = this.state.graph.getNodeAttributes(targetId)

    if (edge.hierRole === "target_is_parent") {
      return {
        source: calculateArrowHeadGeometry(source, target, edge, {
          extremity: "source",
          shape: "father",
          pointing: "away-from-extremity"
        }),
        target: calculateArrowHeadGeometry(source, target, edge, {
          extremity: "target",
          shape: "father",
          pointing: "toward-extremity"
        })
      }
    }

    if (edge.hierRole === "target_is_child") {
      return {
        source: calculateArrowHeadGeometry(source, target, edge, {
          extremity: "source",
          shape: "child",
          pointing: "toward-extremity"
        }),
        target: calculateArrowHeadGeometry(source, target, edge, {
          extremity: "target",
          shape: "child",
          pointing: "away-from-extremity"
        })
      }
    }

    if (edge.hierRole === "same_level") {
      return {
        target: calculateArrowHeadGeometry(source, target, edge, {
          extremity: "target",
          shape: "brother",
          pointing: "toward-extremity"
        }),
        source: calculateArrowHeadGeometry(source, target, edge, {
          extremity: "source",
          shape: "brother",
          pointing: "toward-extremity"
        })
      }
    }

    return null
  }

  createNoteFromPromise(title) {
    const normalizedTitle = title?.trim()
    if (!normalizedTitle) return

    const form = document.createElement("form")
    form.method = "post"
    form.action = "/notes"
    form.hidden = true

    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content
    if (csrfToken) form.appendChild(this.hiddenInput("authenticity_token", csrfToken))
    form.appendChild(this.hiddenInput("note[title]", normalizedTitle))

    document.body.appendChild(form)
    submitFormWithPageTransition(form, { kind: "graph-to-note" })
  }

  handleWindowMouseMove(event) {
    if (this.dragState?.nodeId) {
      event.preventDefault()
      this.dragNodeToPointer(event)
      return
    }

    if (this.nodePressState) {
      this.nodePressState.latestPointer = this.pointerFromMouseEvent(event)

      const movedDistance = Math.hypot(
        this.nodePressState.latestPointer.x - this.nodePressState.pointerStart.x,
        this.nodePressState.latestPointer.y - this.nodePressState.pointerStart.y
      )

      if (movedDistance >= this.constructor.NODE_DRAG_MOVE_TOLERANCE) {
        this.activateNodeDrag()
        this.dragNodeToPointer(event)
        return
      }
    }

    if (!this.stagePanState || this.stagePanState.released) return

    const pointer = this.pointerFromMouseEvent(event)
    if (!pointer) return

    const movedDistance = Math.hypot(
      pointer.x - this.stagePanState.pointerStart.x,
      pointer.y - this.stagePanState.pointerStart.y
    )

    if (movedDistance >= 6) {
      this.releaseFocusForStagePan()
      this.stagePanState.released = true
    }
  }

  handleWindowMouseUp(event) {
    if (this.dragState?.nodeId) {
      const { nodeId } = this.dragState

      this.dragState = null
      this.state.ui.draggingNodeId = null
      this.state.ui.draggedNodeMoved = false
      this.resetMouseCaptorState()
      this.setCameraDraggingEnabled(true)
      this.clearNodePressState()
      event?.preventDefault?.()

      this.state.ui.hoveredNodeId = nodeId
      this.applyDisplayState({ relayout: false, animateFocus: false })
      return
    }

    if (this.nodePressState?.nodeId) {
      const nodePressState = this.nodePressState
      const pointer = this.pointerFromMouseEvent(event)
      const movedDistance = pointer
        ? Math.hypot(
          pointer.x - nodePressState.pointerStart.x,
          pointer.y - nodePressState.pointerStart.y
        )
        : 0
      const isQuickClick = (Date.now() - nodePressState.downAt) < this.constructor.NODE_HOLD_MS
      const nodeId = nodePressState.nodeId

      this.clearNodePressState()
      event?.preventDefault?.()

      if (isQuickClick && movedDistance <= this.constructor.NODE_CLICK_MOVE_TOLERANCE) {
        this.recordRecentClick(nodeId, pointer || nodePressState.pointerStart)
        if (this.embeddedModeValue && nodeId !== this.initialFocusedNodeIdValue) {
          const slug = this.state.graph.getNodeAttribute(nodeId, "slug")
          this.visit(`/notes/${slug}`, { kind: "graph-to-note" })
          return
        }
        this.enterFocusMode(nodeId)
      }
    }

    if (!this.dragState?.nodeId) {
      this.stagePanState = null
    }
  }

  releaseFocusForStagePan() {
    this.state.layout.basePositions = captureNodePositions(this.state.graph)
    this.state.ui.focusedNodeId = null
    this.state.ui.pinnedTooltipNodeId = null
    this.state.ui.hoveredNodeId = null
    this.state.layout.animationToken += 1
    this.applyDisplayState({ relayout: false, animateFocus: false })
  }

  dragNodeToPointer(event) {
    if (!this.dragState?.nodeId || !this.state.renderer || !this.state.graph?.hasNode(this.dragState.nodeId)) return

    const pointer = this.pointerFromMouseEvent(event)
    if (!pointer) return

    const movedDistance = Math.hypot(
      pointer.x - this.dragState.pointerStart.x,
      pointer.y - this.dragState.pointerStart.y
    )

    if (movedDistance >= this.constructor.NODE_DRAG_MOVE_TOLERANCE) {
      this.dragState.moved = true
      this.state.ui.draggedNodeMoved = true
    }

    const graphPoint = this.state.renderer.viewportToGraph(pointer)
    const x = graphPoint.x + this.dragState.offsetX
    const y = graphPoint.y + this.dragState.offsetY

    this.state.graph.mergeNodeAttributes(this.dragState.nodeId, { x, y })
    this.state.layout.manualPositions.set(this.dragState.nodeId, { x, y })
    if (this.state.layout.basePositions?.has(this.dragState.nodeId)) {
      this.state.layout.basePositions.set(this.dragState.nodeId, { x, y })
    }
    this.applyDragFollowerPositions(x, y)

    this.state.renderer.refresh()
    this.positionTooltip()
  }

  activateNodeDrag() {
    if (!this.nodePressState?.nodeId || !this.state.renderer || !this.state.graph?.hasNode(this.nodePressState.nodeId)) return

    const { nodeId, latestPointer, startPosition } = this.nodePressState
    const pointer = latestPointer || this.nodePressState.pointerStart
    const graphPoint = this.state.renderer.viewportToGraph(pointer)

    this.cancelGraphMotion()

    this.dragState = {
      nodeId,
      pointerStart: this.nodePressState.pointerStart,
      offsetX: startPosition.x - graphPoint.x,
      offsetY: startPosition.y - graphPoint.y,
      moved: false,
      startPosition,
      followerPositions: this.captureDragFollowerPositions(nodeId)
    }

    this.state.ui.draggingNodeId = nodeId
    this.state.ui.draggedNodeMoved = false
    this.setCameraDraggingEnabled(false)
    this.resetMouseCaptorState()
  }

  captureDragFollowerPositions(nodeId) {
    const followerPositions = new Map()

    this.state.graph.forEachNode((candidateNodeId, attributes) => {
      if (candidateNodeId === nodeId) return

      const depth = this.resolveDragFollowerDepth(nodeId, candidateNodeId)
      if (depth > 2) return

      followerPositions.set(candidateNodeId, {
        x: attributes.x,
        y: attributes.y,
        depth
      })
    })

    return followerPositions
  }

  resolveDragFollowerDepth(anchorNodeId, candidateNodeId) {
    const cache = this.state.indexes?.neighborDepthCache?.get(anchorNodeId)
    if (cache?.[1]?.has(candidateNodeId)) return 1
    if (cache?.[2]?.has(candidateNodeId)) return 2
    return 999
  }

  applyDragFollowerPositions(nextX, nextY) {
    if (!this.dragState?.followerPositions?.size) return

    const deltaX = nextX - this.dragState.startPosition.x
    const deltaY = nextY - this.dragState.startPosition.y

    this.dragState.followerPositions.forEach((entry, followerNodeId) => {
      const influence = entry.depth === 1 ? 0.34 : 0.16
      const x = entry.x + (deltaX * influence)
      const y = entry.y + (deltaY * influence)

      this.state.graph.mergeNodeAttributes(followerNodeId, { x, y })
      this.state.layout.manualPositions.set(followerNodeId, { x, y })
      if (this.state.layout.basePositions?.has(followerNodeId)) {
        this.state.layout.basePositions.set(followerNodeId, { x, y })
      }
    })
  }

  clearNodePressState() {
    if (this.nodePressState?.holdTimer) {
      window.clearTimeout(this.nodePressState.holdTimer)
    }
    this.nodePressState = null
  }

  enterFocusMode(nodeId) {
    if (!nodeId) return

    this.state.ui.hoveredNodeId = nodeId
    this.state.ui.focusedNodeId = nodeId
    this.state.ui.pinnedTooltipNodeId = nodeId
    this.state.ui.focusDepth = 2
    if (this.hasFocusDepthTarget) this.focusDepthTarget.value = "2"
    this.prioritizeFocusedNodeTags(nodeId)
    this.renderSidebar()
    this.applyDisplayState({ relayout: true, animateFocus: true })
  }

  recordRecentClick(nodeId, pointer) {
    this.recentClickState = {
      nodeId,
      at: Date.now(),
      pointer
    }
  }

  resolveDoubleClickNodeId(event) {
    const directNodeId = this.nodeAtPointer(event)
    if (directNodeId) return directNodeId

    const recentClickState = this.recentClickState
    if (!recentClickState) return null
    if ((Date.now() - recentClickState.at) > this.constructor.NODE_DOUBLE_CLICK_GRACE_MS) return null

    const pointer = this.pointerFromMouseEvent(event)
    if (!pointer || !recentClickState.pointer) return recentClickState.nodeId

    const distance = Math.hypot(
      pointer.x - recentClickState.pointer.x,
      pointer.y - recentClickState.pointer.y
    )

    return distance <= 56 ? recentClickState.nodeId : null
  }

  cancelGraphMotion() {
    this.state.layout.animationToken += 1
    cancelCameraAnimation(this.state.renderer, this.state)
  }

  pointerFromMouseEvent(event) {
    if (!this._mouseLayer) return null

    const rect = this._mouseLayer.getBoundingClientRect()
    return {
      x: event.clientX - rect.left,
      y: event.clientY - rect.top
    }
  }

  setCameraDraggingEnabled(enabled) {
    if (this.state.renderer?.mouseCaptor) this.state.renderer.mouseCaptor.enabled = enabled
  }

  applyTagOrderChange(mutator, options = {}) {
    const beforePositions = this.captureTagRowPositions()
    mutator()
    this.renderSidebar()
    this.animateTagRowReorder(beforePositions)
    this.applyDisplayState({ relayout: false, animateFocus: false })
    this.focusTagRow(options.focusTagId)
  }

  captureTagRowPositions() {
    if (!this.hasTagListTarget) return new Map()

    return new Map(
      [...this.tagListTarget.querySelectorAll("[data-tag-id]")].map((row) => [
        row.dataset.tagId,
        row.getBoundingClientRect().top
      ])
    )
  }

  animateTagRowReorder(beforePositions) {
    if (!this.hasTagListTarget || !beforePositions?.size) return

    const rows = [...this.tagListTarget.querySelectorAll("[data-tag-id]")]
    rows.forEach((row) => {
      const previousTop = beforePositions.get(row.dataset.tagId)
      if (previousTop == null) return

      const nextTop = row.getBoundingClientRect().top
      const deltaY = previousTop - nextTop
      if (Math.abs(deltaY) < 1) return

      row.style.transition = "none"
      row.style.transform = `translateY(${deltaY}px)`

      requestAnimationFrame(() => {
        row.style.transition = ""
        row.style.transform = ""
      })
    })
  }

  focusTagRow(tagId) {
    if (!tagId || !this.hasTagListTarget) return

    const row = this.tagListTarget.querySelector(`[data-tag-id="${CSS.escape(tagId)}"]`)
    row?.focus()
  }

  resetMouseCaptorState() {
    const captor = this.state.renderer?.mouseCaptor
    if (!captor) return

    if (typeof captor.movingTimeout === "number") {
      clearTimeout(captor.movingTimeout)
      captor.movingTimeout = null
    }

    captor.isMouseDown = false
    captor.isMoving = false
    captor.draggedEvents = 0
    captor.startCameraState = null
    captor.lastMouseX = null
    captor.lastMouseY = null
    captor.downStartTime = null
  }

  async toggleFocusedNodeTag(tagId) {
    const nodeId = this.state.ui.focusedNodeId
    if (!nodeId || !this.state.graph?.hasNode(nodeId)) return

    const tagKey = String(tagId)
    const noteId = this.state.graph.getNodeAttribute(nodeId, "id")
    const noteTags = [...(this.state.graph.getNodeAttribute(nodeId, "noteTags") || [])].map(String)
    const isAttached = noteTags.includes(tagKey)
    const method = isAttached ? "DELETE" : "POST"
    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content || ""
    const payload = JSON.stringify({ note_id: String(noteId), tag_id: tagKey })

    const response = await fetch("/note_tags", {
      method,
      headers: {
        "Accept": "application/json",
        "Content-Type": "application/json",
        "X-CSRF-Token": csrfToken
      },
      body: payload,
      credentials: "same-origin"
    })

    if (!response.ok) {
      console.error("Failed to toggle note tag", { nodeId, tagId, method, status: response.status })
      return
    }

    const nextTags = isAttached
      ? noteTags.filter((currentTagId) => currentTagId !== tagKey)
      : [...noteTags, tagKey]

    this.state.graph.setNodeAttribute(nodeId, "noteTags", [...new Set(nextTags)])
    this.state.indexes.tagsByNoteId.set(nodeId, [...new Set(nextTags)])

    const currentNoteTags = this.state.dataset.noteTags || []
    this.state.dataset.noteTags = isAttached
      ? currentNoteTags.filter((row) => !(String(row.note_id) === String(noteId) && String(row.tag_id) === tagKey))
      : [...currentNoteTags, { note_id: noteId, tag_id: tagKey }]

    if (!isAttached) {
      this.state.ui.activeTagsOrdered = moveTagToFront(this.state.ui.activeTagsOrdered, tagKey)
    }

    this.renderSidebar()
    this.applyDisplayState({ relayout: false, animateFocus: false })
  }

  prioritizeFocusedNodeTags(nodeId = this.state.ui.focusedNodeId) {
    if (!nodeId || !this.state.graph?.hasNode(nodeId)) return

    const noteTags = [...(this.state.graph.getNodeAttribute(nodeId, "noteTags") || [])].map(String)
    this.state.ui.activeTagsOrdered = moveTagsToFront(this.state.ui.activeTagsOrdered, noteTags)
  }

  hiddenInput(name, value) {
    const input = document.createElement("input")
    input.type = "hidden"
    input.name = name
    input.value = value
    return input
  }
}
