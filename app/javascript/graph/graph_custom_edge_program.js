import {
  EdgeProgram,
  createEdgeCompoundProgram
} from "sigma/rendering"
import { floatColor } from "sigma/utils"

const MARKER_SHAPES = {
  father: {
    depth: 6.4,
    triangles: [
      [0, 0, 4.8, -2.25, 6.4, 0],
      [0, 0, 6.4, 0, 4.8, 2.25]
    ]
  },
  brother: {
    depth: 4.8,
    triangles: [
      [0, 0, 4.8, -2.2, 4.8, 2.2],
      [4.8, -2.2, 4.8, 2.2, 4.8, 2.2]
    ]
  },
  child: {
    depth: 5.1,
    triangles: [
      [0, 0, 5.1, -2.25, 3.2, 0],
      [0, 0, 3.2, 0, 5.1, 2.25]
    ]
  }
}

const ROLE_MARKER_CONFIG = {
  target_is_parent: {
    type: "father",
    source: {
      shape: "father",
      pointing: "away-from-extremity",
      brightnessBoost: 0.22,
      programClassName: "FatherSourceMarkerProgram"
    },
    target: {
      shape: "father",
      pointing: "toward-extremity",
      brightnessBoost: 0.22,
      programClassName: "FatherTargetMarkerProgram"
    }
  },
  same_level: {
    type: "brother",
    source: {
      shape: "brother",
      pointing: "toward-extremity",
      brightnessBoost: 0.18,
      programClassName: "BrotherSourceMarkerProgram"
    },
    target: {
      shape: "brother",
      pointing: "toward-extremity",
      brightnessBoost: 0.18,
      programClassName: "BrotherTargetMarkerProgram"
    }
  },
  target_is_child: {
    type: "child",
    source: {
      shape: "child",
      pointing: "toward-extremity",
      brightnessBoost: 0.2,
      programClassName: "ChildSourceMarkerProgram"
    },
    target: {
      shape: "child",
      pointing: "away-from-extremity",
      brightnessBoost: 0.2,
      programClassName: "ChildTargetMarkerProgram"
    }
  }
}

export function resolveSigmaEdgeType(hierRole) {
  if (hierRole === "target_is_parent") return "father"
  if (hierRole === "target_is_child") return "child"
  if (hierRole === "same_level") return "brother"
  return "line"
}

export function resolveArrowDirectionHint(hierRole) {
  if (hierRole === "target_is_parent") return "target"
  if (hierRole === "target_is_child") return "source"
  if (hierRole === "same_level") return "both"
  return "none"
}

export function createEdgeProgramClasses() {
  return {
    line: createAsymmetricClampedProgram(),
    father: createEdgeCompoundProgram([
      createNamedBodyProgram("ArrowTargetBodyProgram"),
      createMarkerProgram({ extremity: "source", ...ROLE_MARKER_CONFIG.target_is_parent.source }),
      createMarkerProgram({ extremity: "target", ...ROLE_MARKER_CONFIG.target_is_parent.target })
    ]),
    child: createEdgeCompoundProgram([
      createNamedBodyProgram("ArrowSourceBodyProgram"),
      createMarkerProgram({ extremity: "source", ...ROLE_MARKER_CONFIG.target_is_child.source }),
      createMarkerProgram({ extremity: "target", ...ROLE_MARKER_CONFIG.target_is_child.target })
    ]),
    brother: createEdgeCompoundProgram([
      createNamedBodyProgram("ArrowBothBodyProgram"),
      createMarkerProgram({ extremity: "source", ...ROLE_MARKER_CONFIG.same_level.source }),
      createMarkerProgram({ extremity: "target", ...ROLE_MARKER_CONFIG.same_level.target })
    ])
  }
}

function createNamedBodyProgram(name) {
  const programClass = createAsymmetricClampedProgram()
  Object.defineProperty(programClass, "name", { value: name })
  return programClass
}

const FLOAT = WebGLRenderingContext.FLOAT
const UNSIGNED_BYTE = WebGLRenderingContext.UNSIGNED_BYTE

const EDGE_BODY_FRAGMENT_SHADER = /* glsl */ `
precision mediump float;

varying vec4 v_color;
varying vec2 v_normal;
varying float v_thickness;
varying float v_feather;
varying float v_progress;

uniform float u_animationTime;
uniform float u_animationMode;

const vec4 transparent = vec4(0.0, 0.0, 0.0, 0.0);

void main(void) {
  #ifdef PICKING_MODE
  gl_FragColor = v_color;
  #else
  float dist = length(v_normal) * v_thickness;
  float t = smoothstep(v_thickness - v_feather, v_thickness, dist);
  vec4 baseColor = mix(v_color, transparent, t);
  float directionalProgress = v_progress;

  if (u_animationMode < -0.5) directionalProgress = 1.0 - directionalProgress;
  if (u_animationMode > 1.5) directionalProgress = abs(v_progress - 0.5) * 2.0;

  float waveHead = fract(u_animationTime * 0.42);
  float waveDistance = abs(directionalProgress - waveHead);
  waveDistance = min(waveDistance, 1.0 - waveDistance);
  float glow = smoothstep(0.18, 0.0, waveDistance) * step(0.5, abs(u_animationMode));

  vec3 animatedRgb = mix(baseColor.rgb, vec3(1.0), glow * 0.22);
  float animatedAlpha = min(1.0, baseColor.a + glow * 0.18);
  gl_FragColor = vec4(animatedRgb, animatedAlpha);
  #endif
}
`

const EDGE_BODY_VERTEX_SHADER = /* glsl */ `
attribute vec4 a_id;
attribute vec4 a_color;
attribute vec2 a_normal;
attribute float a_normalCoef;
attribute vec2 a_positionStart;
attribute vec2 a_positionEnd;
attribute float a_positionCoef;
attribute float a_sourceRadius;
attribute float a_targetRadius;
attribute float a_sourceRadiusCoef;
attribute float a_targetRadiusCoef;

uniform mat3 u_matrix;
uniform float u_zoomRatio;
uniform float u_sizeRatio;
uniform float u_pixelRatio;
uniform float u_correctionRatio;
uniform float u_minEdgeThickness;
uniform float u_feather;

varying vec4 v_color;
varying vec2 v_normal;
varying float v_thickness;
varying float v_feather;
varying float v_progress;

const float bias = 255.0 / 254.0;

void main() {
  float minThickness = u_minEdgeThickness;
  vec2 normal = a_normal * a_normalCoef;
  vec2 position = a_positionStart * (1.0 - a_positionCoef) + a_positionEnd * a_positionCoef;
  float normalLength = length(normal);
  vec2 unitNormal = normal / normalLength;
  float pixelsThickness = max(normalLength, minThickness * u_sizeRatio);
  float webGLThickness = pixelsThickness * u_correctionRatio / u_sizeRatio;

  float sourceRadius = a_sourceRadius * a_sourceRadiusCoef;
  float sourceDirection = sign(sourceRadius);
  float webGLSourceRadius = sourceDirection * sourceRadius * 2.0 * u_correctionRatio / u_sizeRatio;
  vec2 sourceCompensationVector =
    vec2(-sourceDirection * unitNormal.y, sourceDirection * unitNormal.x) * webGLSourceRadius;

  float targetRadius = a_targetRadius * a_targetRadiusCoef;
  float targetDirection = sign(targetRadius);
  float webGLTargetRadius = targetDirection * targetRadius * 2.0 * u_correctionRatio / u_sizeRatio;
  vec2 targetCompensationVector =
    vec2(-targetDirection * unitNormal.y, targetDirection * unitNormal.x) * webGLTargetRadius;

  gl_Position = vec4((u_matrix * vec3(position + unitNormal * webGLThickness + sourceCompensationVector + targetCompensationVector, 1)).xy, 0, 1);
  v_thickness = webGLThickness / u_zoomRatio;
  v_normal = unitNormal;
  v_feather = u_feather * u_correctionRatio / u_zoomRatio / u_pixelRatio * 2.0;
  v_progress = a_positionCoef;

  #ifdef PICKING_MODE
  v_color = a_id;
  #else
  v_color = a_color;
  #endif

  v_color.a *= bias;
}
`

const EDGE_ARROW_FRAGMENT_SHADER = /* glsl */ `
precision mediump float;

varying vec4 v_color;
uniform float u_brightnessBoost;

void main(void) {
  #ifdef PICKING_MODE
  gl_FragColor = v_color;
  #else
  vec3 boostedRgb = mix(v_color.rgb, vec3(1.0), u_brightnessBoost);
  float boostedAlpha = min(1.0, v_color.a + u_brightnessBoost * 0.24);
  gl_FragColor = vec4(boostedRgb, boostedAlpha);
  #endif
}
`

const EDGE_ARROW_VERTEX_SHADER = /* glsl */ `
attribute vec4 a_id;
attribute vec4 a_color;
attribute vec2 a_positionStart;
attribute vec2 a_positionEnd;
attribute float a_radius;
attribute float a_thickness;
attribute vec2 a_shapePoint;

uniform mat3 u_matrix;
uniform float u_sizeRatio;
uniform float u_correctionRatio;
uniform float u_minEdgeThickness;

varying vec4 v_color;

const float bias = 255.0 / 254.0;

void main() {
  vec2 delta = a_positionEnd - a_positionStart;
  float deltaLength = length(delta);
  vec2 safeDelta = deltaLength > 0.0 ? delta / deltaLength : vec2(0.0, 1.0);
  float pixelsThickness = max(a_thickness, u_minEdgeThickness * u_sizeRatio);
  float webGLThickness = pixelsThickness * u_correctionRatio / u_sizeRatio;
  float direction = sign(a_radius);
  float webGLNodeRadius = abs(a_radius) * 2.0 * u_correctionRatio / u_sizeRatio;
  vec2 extremity = direction < 0.0
    ? a_positionStart + safeDelta * webGLNodeRadius
    : a_positionEnd - safeDelta * webGLNodeRadius;
  vec2 inwardDirection = direction < 0.0 ? safeDelta : -safeDelta;
  vec2 lateralDirection = vec2(-inwardDirection.y, inwardDirection.x);
  vec2 position =
    extremity +
    inwardDirection * (a_shapePoint.x * webGLThickness * 2.0) +
    lateralDirection * (a_shapePoint.y * webGLThickness * 2.0);

  gl_Position = vec4((u_matrix * vec3(position, 1)).xy, 0, 1);

  #ifdef PICKING_MODE
  v_color = a_id;
  #else
  v_color = a_color;
  #endif

  v_color.a *= bias;
  }
`

function roleMarkerPadding(hierRole, edgeSize, extremity) {
  const config = ROLE_MARKER_CONFIG[hierRole]?.[extremity]
  if (!config) return 0
  if (extremity === "source") return 2
  return 8
}

function markerThicknessForRole(hierRole, fallbackThickness) {
  if (hierRole === "target_is_parent") return 3.2
  if (hierRole === "target_is_child") return 3.2
  if (hierRole === "same_level") return 3.2
  return fallbackThickness
}

function shapeTrianglesForPointing(shapeName, pointing) {
  const shape = MARKER_SHAPES[shapeName]
  if (!shape) return MARKER_SHAPES.brother.triangles
  if (pointing !== "away-from-extremity") return shape.triangles

  return shape.triangles.map((triangle) => {
    const reflected = []

    for (let index = 0; index < triangle.length; index += 2) {
      reflected.push(shape.depth - triangle[index], triangle[index + 1])
    }

    return reflected
  })
}

function createAsymmetricClampedProgram() {
  return class AsymmetricClampedProgram extends EdgeProgram {
    getDefinition() {
      return {
        VERTICES: 6,
        VERTEX_SHADER_SOURCE: EDGE_BODY_VERTEX_SHADER,
        FRAGMENT_SHADER_SOURCE: EDGE_BODY_FRAGMENT_SHADER,
        METHOD: WebGLRenderingContext.TRIANGLES,
        UNIFORMS: ["u_matrix", "u_zoomRatio", "u_sizeRatio", "u_correctionRatio", "u_pixelRatio", "u_feather", "u_minEdgeThickness", "u_animationTime", "u_animationMode"],
        ATTRIBUTES: [
          { name: "a_positionStart", size: 2, type: FLOAT },
          { name: "a_positionEnd", size: 2, type: FLOAT },
          { name: "a_normal", size: 2, type: FLOAT },
          { name: "a_color", size: 4, type: UNSIGNED_BYTE, normalized: true },
          { name: "a_id", size: 4, type: UNSIGNED_BYTE, normalized: true },
          { name: "a_sourceRadius", size: 1, type: FLOAT },
          { name: "a_targetRadius", size: 1, type: FLOAT }
        ],
        CONSTANT_ATTRIBUTES: [
          { name: "a_positionCoef", size: 1, type: FLOAT },
          { name: "a_normalCoef", size: 1, type: FLOAT },
          { name: "a_sourceRadiusCoef", size: 1, type: FLOAT },
          { name: "a_targetRadiusCoef", size: 1, type: FLOAT }
        ],
        CONSTANT_DATA: [
          [0, 1, -1, 0],
          [0, -1, 1, 0],
          [1, 1, 0, 1],
          [1, 1, 0, 1],
          [0, -1, 1, 0],
          [1, -1, 0, -1]
        ]
      }
    }

    processVisibleItem(edgeIndex, startIndex, sourceData, targetData, data) {
      const thickness = markerThicknessForRole(data.hierRole, data.size || 1)
      const x1 = sourceData.x
      const y1 = sourceData.y
      const x2 = targetData.x
      const y2 = targetData.y
      const color = floatColor(data.color)
      const dx = x2 - x1
      const dy = y2 - y1
      let len = dx * dx + dy * dy
      let n1 = 0
      let n2 = 0

      if (len) {
        len = 1 / Math.sqrt(len)
        n1 = -dy * len * thickness
        n2 = dx * len * thickness
      }

      const sourceRadius = (sourceData.size || 1) + (data.srcPadding ?? 0)
      const targetRadius = (targetData.size || 1) + (data.dstPadding ?? 0)
      const array = this.array
      array[startIndex++] = x1
      array[startIndex++] = y1
      array[startIndex++] = x2
      array[startIndex++] = y2
      array[startIndex++] = n1
      array[startIndex++] = n2
      array[startIndex++] = color
      array[startIndex++] = edgeIndex
      array[startIndex++] = sourceRadius
      array[startIndex++] = targetRadius
    }

    setUniforms(params, { gl, uniformLocations }) {
      gl.uniformMatrix3fv(uniformLocations.u_matrix, false, params.matrix)
      gl.uniform1f(uniformLocations.u_zoomRatio, params.zoomRatio)
      gl.uniform1f(uniformLocations.u_sizeRatio, params.sizeRatio)
      gl.uniform1f(uniformLocations.u_correctionRatio, params.correctionRatio)
      gl.uniform1f(uniformLocations.u_pixelRatio, params.pixelRatio)
      gl.uniform1f(uniformLocations.u_feather, params.antiAliasingFeather)
      gl.uniform1f(uniformLocations.u_minEdgeThickness, params.minEdgeThickness)
      gl.uniform1f(uniformLocations.u_animationTime, performance.now() / 1000)
      gl.uniform1f(uniformLocations.u_animationMode, resolveAnimationMode(this.constructor.name))
    }
  }
}

function resolveAnimationMode(programName) {
  if (programName.includes("ArrowSource")) return -1
  if (programName.includes("ArrowBoth")) return 2
  if (programName.includes("ArrowTarget")) return 1
  return 0
}

function createMarkerProgram(inputOptions = {}) {
  const options = {
    extremity: "target",
    shape: "brother",
    pointing: "toward-extremity",
    brightnessBoost: 0.16,
    programClassName: "MarkerProgram",
    ...inputOptions
  }

  const triangles = shapeTrianglesForPointing(options.shape, options.pointing)
  const constantData = triangles.flatMap((triangle) => ([
    [triangle[0], triangle[1]],
    [triangle[2], triangle[3]],
    [triangle[4], triangle[5]]
  ]))

  const programClass = class MarkerProgram extends EdgeProgram {
    getDefinition() {
      return {
        VERTICES: constantData.length,
        VERTEX_SHADER_SOURCE: EDGE_ARROW_VERTEX_SHADER,
        FRAGMENT_SHADER_SOURCE: EDGE_ARROW_FRAGMENT_SHADER,
        METHOD: WebGLRenderingContext.TRIANGLES,
        UNIFORMS: ["u_matrix", "u_sizeRatio", "u_correctionRatio", "u_minEdgeThickness", "u_brightnessBoost"],
        ATTRIBUTES: [
          { name: "a_positionStart", size: 2, type: FLOAT },
          { name: "a_positionEnd", size: 2, type: FLOAT },
          { name: "a_radius", size: 1, type: FLOAT },
          { name: "a_thickness", size: 1, type: FLOAT },
          { name: "a_color", size: 4, type: UNSIGNED_BYTE, normalized: true },
          { name: "a_id", size: 4, type: UNSIGNED_BYTE, normalized: true }
        ],
        CONSTANT_ATTRIBUTES: [{ name: "a_shapePoint", size: 2, type: FLOAT }],
        CONSTANT_DATA: constantData
      }
    }

    processVisibleItem(edgeIndex, startIndex, sourceData, targetData, data) {
      const thickness = data.size || 1
      const x1 = sourceData.x
      const y1 = sourceData.y
      const x2 = targetData.x
      const y2 = targetData.y
      const color = floatColor(data.color)
      const extremityData = options.extremity === "source" ? sourceData : targetData
      const padding = options.extremity === "source" ? (data.srcPadding ?? 0) : (data.dstPadding ?? 0)
      const radius = ((extremityData.size || 1) + padding) * (options.extremity === "source" ? -1 : 1)
      const array = this.array
      array[startIndex++] = x1
      array[startIndex++] = y1
      array[startIndex++] = x2
      array[startIndex++] = y2
      array[startIndex++] = radius
      array[startIndex++] = thickness
      array[startIndex++] = color
      array[startIndex++] = edgeIndex
    }

    setUniforms(params, { gl, uniformLocations }) {
      gl.uniformMatrix3fv(uniformLocations.u_matrix, false, params.matrix)
      gl.uniform1f(uniformLocations.u_sizeRatio, params.sizeRatio)
      gl.uniform1f(uniformLocations.u_correctionRatio, params.correctionRatio)
      gl.uniform1f(uniformLocations.u_minEdgeThickness, params.minEdgeThickness)
      gl.uniform1f(uniformLocations.u_brightnessBoost, options.brightnessBoost)
    }
  }

  Object.defineProperty(programClass, "name", { value: options.programClassName })
  return programClass
}

export function calculateArrowHeadGeometry(source, target, edge, options = {}) {
  const extremity = options.extremity || "target"
  const shapeName = options.shape || "brother"
  const pointing = options.pointing || "toward-extremity"
  const triangles = shapeTrianglesForPointing(shapeName, pointing)
  const dx = target.x - source.x
  const dy = target.y - source.y
  const length = Math.hypot(dx, dy) || 1
  const dirX = dx / length
  const dirY = dy / length
  const thickness = markerThicknessForRole(edge.hierRole, edge.size || 1)
  const padding = extremity === "source" ? (edge.srcPadding ?? 0) : (edge.dstPadding ?? 0)
  const radius = extremity === "source" ? ((source.size || 1) + padding) : ((target.size || 1) + padding)
  const contact = extremity === "source"
    ? { x: source.x + dirX * radius, y: source.y + dirY * radius }
    : { x: target.x - dirX * radius, y: target.y - dirY * radius }
  const inward = extremity === "source"
    ? { x: dirX, y: dirY }
    : { x: -dirX, y: -dirY }
  const lateral = { x: -inward.y, y: inward.x }
  const vertices = triangles.flatMap((triangle) => {
    const points = []

    for (let index = 0; index < triangle.length; index += 2) {
      const axial = triangle[index] * thickness
      const lateralOffset = triangle[index + 1] * thickness
      points.push({
        x: contact.x + inward.x * axial + lateral.x * lateralOffset,
        y: contact.y + inward.y * axial + lateral.y * lateralOffset
      })
    }

    return points
  })

  return { contact, vertices }
}

export function edgePaddingForRole(hierRole, edgeSize, extremity) {
  return roleMarkerPadding(hierRole, edgeSize, extremity)
}
