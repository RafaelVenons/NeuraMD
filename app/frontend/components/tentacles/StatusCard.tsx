import { ClawdAvatar } from "~/components/graph/ClawdAvatar"
import { AgentStateBadge } from "~/components/tentacles/AgentStateBadge"
import type { TilingCard } from "~/components/tentacles/tilingLayout"

type Props = {
  card: TilingCard
  onPromote: (tentacleId: string) => void
}

export function StatusCard({ card, onPromote }: Props) {
  const { session } = card
  const id = session.tentacle_id
  const title = session.title || id

  return (
    <button
      type="button"
      className="nm-tiling__card"
      onClick={() => onPromote(id)}
      data-tentacle-id={id}
      title={`Promover "${title}" para tile ativo`}
    >
      <span className="nm-tiling__card-avatar" aria-hidden>
        <svg width={18} height={18} viewBox="-9 -9 18 18">
          <ClawdAvatar state="awake" color="#7aa2f7" size={18} />
        </svg>
      </span>
      <span className="nm-tiling__card-body">
        <span className="nm-tiling__card-title">{title}</span>
        <AgentStateBadge tentacleId={id} fallback={session.alive ? "processing" : "idle"} />
      </span>
    </button>
  )
}
