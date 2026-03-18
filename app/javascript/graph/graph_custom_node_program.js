import { NodeProgram, createNodeCompoundProgram } from "sigma/rendering"
import { floatColor } from "sigma/utils"

const FLOAT = WebGLRenderingContext.FLOAT
const UNSIGNED_BYTE = WebGLRenderingContext.UNSIGNED_BYTE

const NODE_FRAGMENT_SHADER = /* glsl */ `
precision highp float;

varying vec4 v_color;
varying vec2 v_diffVector;
varying float v_radius;

uniform float u_correctionRatio;

const vec4 transparent = vec4(0.0, 0.0, 0.0, 0.0);

void main(void) {
  float border = u_correctionRatio * 2.0;
  float dist = length(v_diffVector) - v_radius + border;

  #ifdef PICKING_MODE
  if (dist > border)
    gl_FragColor = transparent;
  else
    gl_FragColor = v_color;
  #else
  float t = 0.0;
  if (dist > border)
    t = 1.0;
  else if (dist > 0.0)
    t = dist / border;

  gl_FragColor = mix(v_color, transparent, t);
  #endif
}
`

const NODE_VERTEX_SHADER = /* glsl */ `
attribute vec4 a_id;
attribute vec4 a_color;
attribute vec2 a_position;
attribute float a_size;
attribute float a_angle;

uniform mat3 u_matrix;
uniform float u_sizeRatio;
uniform float u_correctionRatio;

varying vec4 v_color;
varying vec2 v_diffVector;
varying float v_radius;

const float bias = 255.0 / 254.0;

void main() {
  float size = a_size * u_correctionRatio / u_sizeRatio * 4.0;
  vec2 diffVector = size * vec2(cos(a_angle), sin(a_angle));
  vec2 position = a_position + diffVector;

  gl_Position = vec4((u_matrix * vec3(position, 1)).xy, 0, 1);

  v_diffVector = diffVector;
  v_radius = size / 2.0;

  #ifdef PICKING_MODE
  v_color = a_id;
  #else
  v_color = a_color;
  #endif

  v_color.a *= bias;
}
`

export function createNodeProgramClasses(drawLabelAbove) {
  return {
    circle: createNodeCompoundProgram(
      [
        createScaledCircleProgram({ sizeMultiplier: 1.24, colorAttribute: "borderColor" }),
        createScaledCircleProgram({ sizeMultiplier: 1.0, colorAttribute: "color" })
      ],
      drawLabelAbove
    )
  }
}

function createScaledCircleProgram(options) {
  const { sizeMultiplier, colorAttribute } = options

  return class ScaledCircleProgram extends NodeProgram {
    static ANGLE_1 = 0
    static ANGLE_2 = (2 * Math.PI) / 3
    static ANGLE_3 = (4 * Math.PI) / 3

    getDefinition() {
      return {
        VERTICES: 3,
        VERTEX_SHADER_SOURCE: NODE_VERTEX_SHADER,
        FRAGMENT_SHADER_SOURCE: NODE_FRAGMENT_SHADER,
        METHOD: WebGLRenderingContext.TRIANGLES,
        UNIFORMS: ["u_sizeRatio", "u_correctionRatio", "u_matrix"],
        ATTRIBUTES: [
          { name: "a_position", size: 2, type: FLOAT },
          { name: "a_size", size: 1, type: FLOAT },
          { name: "a_color", size: 4, type: UNSIGNED_BYTE, normalized: true },
          { name: "a_id", size: 4, type: UNSIGNED_BYTE, normalized: true }
        ],
        CONSTANT_ATTRIBUTES: [{ name: "a_angle", size: 1, type: FLOAT }],
        CONSTANT_DATA: [
          [ScaledCircleProgram.ANGLE_1],
          [ScaledCircleProgram.ANGLE_2],
          [ScaledCircleProgram.ANGLE_3]
        ]
      }
    }

    processVisibleItem(nodeIndex, startIndex, data) {
      const array = this.array
      const color = floatColor(data[colorAttribute] || data.color)

      array[startIndex++] = data.x
      array[startIndex++] = data.y
      array[startIndex++] = (data.size || 1) * sizeMultiplier
      array[startIndex++] = color
      array[startIndex++] = nodeIndex
    }

    setUniforms(params, { gl, uniformLocations }) {
      gl.uniform1f(uniformLocations.u_correctionRatio, params.correctionRatio)
      gl.uniform1f(uniformLocations.u_sizeRatio, params.sizeRatio)
      gl.uniformMatrix3fv(uniformLocations.u_matrix, false, params.matrix)
    }
  }
}
