class TentacleChannel < ApplicationCable::Channel
  def subscribed
    return reject unless Tentacles::Authorization.enabled?

    tentacle_id = params[:tentacle_id]
    return reject unless tentacle_id.present?

    stream_for(tentacle_id)
  end

  def unsubscribed
    # No-op: ownership of the underlying process is tracked in TentacleRuntime.
  end

  def input(payload)
    tentacle_id = params[:tentacle_id]
    data = payload["data"].to_s
    return if data.empty?

    TentacleRuntime.write(tentacle_id: tentacle_id, data: data)
  end

  def resize(payload)
    tentacle_id = params[:tentacle_id]
    cols = payload["cols"].to_i
    rows = payload["rows"].to_i
    return if cols.zero? || rows.zero?

    TentacleRuntime.resize(tentacle_id: tentacle_id, cols: cols, rows: rows)
  end

  def self.broadcast_output(tentacle_id:, data:)
    broadcast_to(tentacle_id, type: "output", data: data)
  end

  def self.broadcast_exit(tentacle_id:, status: nil)
    broadcast_to(tentacle_id, type: "exit", status: status)
  end

  def self.broadcast_context_warning(tentacle_id:, ratio:, estimated_tokens:)
    broadcast_to(
      tentacle_id,
      type: "context-warning",
      ratio: ratio,
      estimated_tokens: estimated_tokens
    )
  end
end
