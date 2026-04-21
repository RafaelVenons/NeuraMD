module Tentacles
  class CronLeaseReleaseJob < ApplicationJob
    queue_as :default

    retry_on ActiveRecord::StatementInvalid, wait: :polynomially_longer, attempts: 10
    retry_on ActiveRecord::ConnectionNotEstablished, wait: :polynomially_longer, attempts: 10

    def perform(note_id:, lease_token:, success:)
      updates = { last_attempted_at: nil, lease_pid: nil, lease_host: nil, lease_token: nil }
      updates[:last_fired_at] = Time.current if success

      TentacleCronState
        .where(note_id: note_id, lease_token: lease_token)
        .update_all(updates)
    end
  end
end
