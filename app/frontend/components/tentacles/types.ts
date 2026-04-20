export type TentacleSession = {
  tentacle_id: string
  alive: boolean
  pid: number | null
  started_at: string | null
  command: string[] | null
}

export type TentacleCableMessage =
  | { type: "output"; data: string }
  | { type: "exit"; status: number | null }
