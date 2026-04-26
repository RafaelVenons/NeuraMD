import { useCallback } from "react"

import { TentacleMiniPanel } from "~/components/tentacles/TentacleMiniPanel"
import type { TilingTile as TilingTileData } from "~/components/tentacles/tilingLayout"

type Props = {
  tile: TilingTileData
  isFocused: boolean
  onFocus: (tentacleId: string) => void
  onSolo: (tentacleId: string) => void
  onRemoved: (tentacleId: string) => void
}

function isInteractiveTarget(el: HTMLElement): boolean {
  return el.closest("button, a, input, textarea, select") !== null
}

export function TilingTile({ tile, isFocused, onFocus, onSolo, onRemoved }: Props) {
  const id = tile.session.tentacle_id

  const handleClick = useCallback(
    (event: React.MouseEvent<HTMLDivElement>) => {
      const target = event.target as HTMLElement
      if (isInteractiveTarget(target)) return
      if (!target.closest("header")) return
      onFocus(id)
    },
    [id, onFocus]
  )

  const handleDoubleClick = useCallback(
    (event: React.MouseEvent<HTMLDivElement>) => {
      const target = event.target as HTMLElement
      if (isInteractiveTarget(target)) return
      if (!target.closest("header")) return
      event.preventDefault()
      onSolo(id)
    },
    [id, onSolo]
  )

  const className = `nm-tiling__tile${isFocused ? " is-focused" : ""}`

  return (
    <div
      className={className}
      style={{
        gridColumn: `${tile.col} / span ${tile.colSpan}`,
        gridRow: `${tile.row} / span ${tile.rowSpan}`,
      }}
      data-tentacle-id={id}
      data-weight={tile.weight.toFixed(3)}
      onClick={handleClick}
      onDoubleClick={handleDoubleClick}
    >
      <TentacleMiniPanel session={tile.session} onRemoved={onRemoved} />
    </div>
  )
}
