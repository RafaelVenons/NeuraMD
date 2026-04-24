import type { SVGProps } from "react"

export type ClawdState = "awake" | "sleeping"

type Props = {
  state: ClawdState
  color: string
  size?: number
} & Pick<SVGProps<SVGGElement>, "pointerEvents">

export function ClawdAvatar({ state, color, size = 22, pointerEvents }: Props) {
  const s = size / 10
  const offset = -size / 2

  return (
    <g transform={`translate(${offset}, ${offset})`} pointerEvents={pointerEvents}>
      <rect
        x={s * 1.5}
        y={s * 1}
        width={s * 1.5}
        height={s * 1.5}
        fill={color}
        stroke="#0b0d10"
        strokeWidth={s * 0.3}
      />
      <rect
        x={s * 7}
        y={s * 1}
        width={s * 1.5}
        height={s * 1.5}
        fill={color}
        stroke="#0b0d10"
        strokeWidth={s * 0.3}
      />
      <rect
        x={s * 1}
        y={s * 2}
        width={s * 8}
        height={s * 7}
        rx={s * 1.5}
        fill={color}
        stroke="#0b0d10"
        strokeWidth={s * 0.4}
      />
      {state === "awake" ? (
        <g data-testid="clawd-eyes-awake">
          <rect x={s * 2.8} y={s * 4} width={s * 1.3} height={s * 1.7} fill="#0b0d10" />
          <rect x={s * 5.9} y={s * 4} width={s * 1.3} height={s * 1.7} fill="#0b0d10" />
          <rect x={s * 3.1} y={s * 4.3} width={s * 0.5} height={s * 0.5} fill="#ffffff" />
          <rect x={s * 6.2} y={s * 4.3} width={s * 0.5} height={s * 0.5} fill="#ffffff" />
        </g>
      ) : (
        <g data-testid="clawd-eyes-sleeping">
          <rect x={s * 2.6} y={s * 5} width={s * 1.7} height={s * 0.4} fill="#0b0d10" />
          <rect x={s * 5.7} y={s * 5} width={s * 1.7} height={s * 0.4} fill="#0b0d10" />
          <text
            x={s * 7.5}
            y={s * 1.8}
            fontSize={s * 2.6}
            fontWeight="bold"
            fontFamily="monospace"
            fill="#0b0d10"
            stroke={color}
            strokeWidth={s * 0.2}
            paintOrder="stroke"
          >
            z
          </text>
        </g>
      )}
      <rect x={s * 4.2} y={s * 7} width={s * 1.6} height={s * 0.5} fill="#0b0d10" />
    </g>
  )
}
