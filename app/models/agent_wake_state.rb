class AgentWakeState < ApplicationRecord
  self.primary_key = :note_id

  belongs_to :note
end
