import {
  EdgeProgram,
  createEdgeCompoundProgram
} from "sigma/rendering"
import { floatColor } from "sigma/utils"

export function resolveSigmaEdgeType(hierRole) {
  if (hierRole === "target_is_parent") return "arrow-target"
  if (hierRole === "target_is_child") return "arrow-source"
  return "line"
}

export function resolveArrowDirectionHint(hierRole) {
  if (hierRole === "target_is_parent") return "target"
  if (hierRole === "target_is_child") return "source"
  return "none"
}

export function createEdgeProgramClasses() {
  return {
    line: createAsymmetricClampedProgram(),
    "arrow-target": createEdgeCompoundProgram([
      createAsymmetricClampedProgram(),
      createAsymmetricArrowHeadProgram()
    ]),
    "arrow-source": createEdgeCompoundProgram([
      createAsymmetricClampedProgram(),
      createAsymmetricArrowHeadProgram({ extremity: "source" })
    ])
  }
}

const FLOAT = WebGLRenderingContext.FLOAT
const UNSIGNED_BYTE = WebGLRenderingContext.UNSIGNED_BYTE

const EDGE_BODY_FRAGMENT_SHADER = /* glsl */ `
precision mediump float;

varying vec4 v_color;
varying vec2 v_normal;
varying float v_thickness;
varying float v_feather;

const vec4 transparent = vec4(0.0, 0.0, 0.0, 0.0);

void main(void) {
  #ifdef PICKING_MODE
  gl_FragColor = v_color;
  #else
  float dist = length(v_normal) * v_thickness;
  float t = smoothstep(v_thickness - v_feather, v_thickness, dist);
  gl_FragColor = mix(v_color, transparent, t);
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
varying vec2 v_normal;
varying float v_thickness;
varying float v_feather;

const vec4 transparent = vec4(0.0, 0.0, 0.0, 0.0);

void main(void) {
  #ifdef PICKING_MODE
  gl_FragColor = v_color;
  #else
  float dist = length(v_normal) * v_thickness;
  float t = smoothstep(v_thickness - v_feather, v_thickness, dist);
  gl_FragColor = mix(v_color, transparent, t);
  #endif
}
`

const EDGE_ARROW_VERTEX_SHADER = /* glsl */ `
attribute vec4 a_id;
attribute vec4 a_color;
attribute vec2 a_position;
attribute vec2 a_normal;
attribute float a_radius;
attribute vec3 a_barycentric;

uniform mat3 u_matrix;
uniform float u_sizeRatio;
uniform float u_correctionRatio;
uniform float u_minEdgeThickness;
uniform float u_lengthToThicknessRatio;
uniform float u_widenessToThicknessRatio;

varying vec4 v_color;
varying vec2 v_normal;
varying float v_thickness;
varying float v_feather;

const float bias = 255.0 / 254.0;

void main() {
  float pixelsThickness = max(length(a_normal), u_minEdgeThickness * u_sizeRatio);
  float webGLThickness = pixelsThickness * u_correctionRatio / u_sizeRatio;
  float direction = sign(a_radius);
  float webGLNodeRadius = direction * a_radius * 2.0 * u_correctionRatio / u_sizeRatio;
  float webGLArrowHeadLength = webGLThickness * u_lengthToThicknessRatio * 2.0;
  float webGLArrowHeadWideness = webGLThickness * u_widenessToThicknessRatio * 2.0;

  vec2 unitNormal = a_normal / length(a_normal);
  vec2 arrowDirection = vec2(-unitNormal.y, unitNormal.x) * direction;
  vec2 normalDirection = unitNormal * (a_barycentric.y - a_barycentric.z);
  vec2 position = a_position + arrowDirection * (webGLNodeRadius + webGLArrowHeadLength * a_barycentric.x) + normalDirection * webGLArrowHeadWideness * a_barycentric.x;

  gl_Position = vec4((u_matrix * vec3(position, 1)).xy, 0, 1);
  v_thickness = webGLArrowHeadWideness / 2.0;
  v_normal = normalDirection;
  v_feather = webGLThickness * 0.25;

  #ifdef PICKING_MODE
  v_color = a_id;
  #else
  v_color = a_color;
  #endif

  v_color.a *= bias;
}
`

function createAsymmetricClampedProgram() {
  return class AsymmetricClampedProgram extends EdgeProgram {
    getDefinition() {
      return {
        VERTICES: 6,
        VERTEX_SHADER_SOURCE: EDGE_BODY_VERTEX_SHADER,
        FRAGMENT_SHADER_SOURCE: EDGE_BODY_FRAGMENT_SHADER,
        METHOD: WebGLRenderingContext.TRIANGLES,
        UNIFORMS: ["u_matrix", "u_zoomRatio", "u_sizeRatio", "u_correctionRatio", "u_pixelRatio", "u_feather", "u_minEdgeThickness"],
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
      const thickness = data.size || 1
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

      const sourceRadius = (sourceData.size || 1) + (data.srcPadding || 4)
      const targetRadius = (targetData.size || 1) + (data.dstPadding || 10)
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
    }
  }
}

function createAsymmetricArrowHeadProgram(inputOptions = {}) {
  const options = {
    extremity: "target",
    lengthToThicknessRatio: 2.5,
    widenessToThicknessRatio: 2,
    ...inputOptions
  }

  return class AsymmetricArrowHeadProgram extends EdgeProgram {
    getDefinition() {
      return {
        VERTICES: 3,
        VERTEX_SHADER_SOURCE: EDGE_ARROW_VERTEX_SHADER,
        FRAGMENT_SHADER_SOURCE: EDGE_ARROW_FRAGMENT_SHADER,
        METHOD: WebGLRenderingContext.TRIANGLES,
        UNIFORMS: ["u_matrix", "u_sizeRatio", "u_correctionRatio", "u_minEdgeThickness", "u_lengthToThicknessRatio", "u_widenessToThicknessRatio"],
        ATTRIBUTES: [
          { name: "a_position", size: 2, type: FLOAT },
          { name: "a_normal", size: 2, type: FLOAT },
          { name: "a_radius", size: 1, type: FLOAT },
          { name: "a_color", size: 4, type: UNSIGNED_BYTE, normalized: true },
          { name: "a_id", size: 4, type: UNSIGNED_BYTE, normalized: true }
        ],
        CONSTANT_ATTRIBUTES: [{ name: "a_barycentric", size: 3, type: FLOAT }],
        CONSTANT_DATA: [
          [1, 0, 0],
          [0, 1, 0],
          [0, 0, 1]
        ]
      }
    }

    processVisibleItem(edgeIndex, startIndex, sourceData, targetData, data) {
      if (options.extremity === "source") {
        ;[sourceData, targetData] = [targetData, sourceData]
      }

      const thickness = data.size || 1
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

      const padding = options.extremity === "source" ? (data.srcPadding || 4) : (data.dstPadding || 10)
      const radius = (targetData.size || 1) + padding
      const array = this.array
      array[startIndex++] = x2
      array[startIndex++] = y2
      array[startIndex++] = -n1
      array[startIndex++] = -n2
      array[startIndex++] = radius
      array[startIndex++] = color
      array[startIndex++] = edgeIndex
    }

    setUniforms(params, { gl, uniformLocations }) {
      gl.uniformMatrix3fv(uniformLocations.u_matrix, false, params.matrix)
      gl.uniform1f(uniformLocations.u_sizeRatio, params.sizeRatio)
      gl.uniform1f(uniformLocations.u_correctionRatio, params.correctionRatio)
      gl.uniform1f(uniformLocations.u_minEdgeThickness, params.minEdgeThickness)
      gl.uniform1f(uniformLocations.u_lengthToThicknessRatio, options.lengthToThicknessRatio)
      gl.uniform1f(uniformLocations.u_widenessToThicknessRatio, options.widenessToThicknessRatio)
    }
  }
}
