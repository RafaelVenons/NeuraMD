import type { SVGProps } from "react"

import type { AvatarHat, AvatarState } from "~/components/graph/types"

export type ClawdState = AvatarState

type Props = {
  state: AvatarState
  color: string
  hat?: AvatarHat
  size?: number
  animateZzz?: boolean
} & Pick<SVGProps<SVGGElement>, "pointerEvents">

export function ClawdAvatar({
  state,
  color,
  hat = "none",
  size = 22,
  pointerEvents,
  animateZzz = false,
}: Props) {
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
            className={animateZzz ? "nm-clawd-zzz" : undefined}
            data-testid="clawd-zzz"
          >
            z
          </text>
        </g>
      )}
      <rect x={s * 4.2} y={s * 7} width={s * 1.6} height={s * 0.5} fill="#0b0d10" />
      <ClawdHat hat={hat} s={s} />
    </g>
  )
}

function ClawdHat({ hat, s }: { hat: AvatarHat; s: number }) {
  if (hat === "none") return null

  if (hat === "cartola") {
    return (
      <g data-testid="clawd-hat-cartola">
        <rect x={s * 2.5} y={s * 0.2} width={s * 5} height={s * 0.4} fill="#0b0d10" />
        <rect x={s * 3.5} y={s * -1.4} width={s * 3} height={s * 1.6} fill="#0b0d10" />
      </g>
    )
  }

  if (hat === "chef") {
    return (
      <g data-testid="clawd-hat-chef">
        <rect x={s * 2.5} y={s * 0.5} width={s * 5} height={s * 0.5} fill="#ffffff" stroke="#0b0d10" strokeWidth={s * 0.2} />
        <rect x={s * 3} y={s * -1.2} width={s * 4} height={s * 1.7} fill="#ffffff" stroke="#0b0d10" strokeWidth={s * 0.2} rx={s * 0.6} />
        <rect x={s * 3.4} y={s * -1.6} width={s * 1.4} height={s * 0.6} fill="#ffffff" stroke="#0b0d10" strokeWidth={s * 0.2} rx={s * 0.4} />
        <rect x={s * 5.2} y={s * -1.8} width={s * 1.4} height={s * 0.7} fill="#ffffff" stroke="#0b0d10" strokeWidth={s * 0.2} rx={s * 0.4} />
      </g>
    )
  }

  return null
}
