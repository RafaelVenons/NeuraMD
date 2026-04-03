DOMAIN_EVENT_CATALOG = {
  "neuramd.note.created" => {payload: %i[note_id slug title], description: "Nota criada"},
  "neuramd.note.updated" => {payload: %i[note_id slug], description: "Conteúdo atualizado"},
  "neuramd.note.renamed" => {payload: %i[note_id old_slug new_slug old_title new_title], description: "Título/slug alterado"},
  "neuramd.note.deleted" => {payload: %i[note_id slug], description: "Nota soft-deleted"},
  "neuramd.note.restored" => {payload: %i[note_id slug], description: "Nota restaurada"},
  "neuramd.link.created" => {payload: %i[src_note_id dst_note_id], description: "Link criado"},
  "neuramd.link.deleted" => {payload: %i[src_note_id dst_note_id], description: "Link removido"},
  "neuramd.property.changed" => {payload: %i[note_id property action value], description: "Propriedade alterada"}
}.freeze

DOMAIN_EVENTS = DOMAIN_EVENT_CATALOG.keys.freeze

module DomainEventSubscriber
  # Subscribe with isolated failure — exceptions in the block are logged, not propagated.
  def self.safe_subscribe(event_name, &block)
    ActiveSupport::Notifications.subscribe(event_name) do |*args|
      block.call(*args)
    rescue => e
      Rails.logger.error("[DomainEvent] Subscriber failed for #{event_name}: #{e.message}")
      Rails.logger.error(e.backtrace&.first(5)&.join("\n"))
    end
  end
end

DomainEventSubscriber.safe_subscribe("neuramd.note.renamed") do |*, payload|
  Links::DisplayTextUpdateService.call(
    renamed_note_id: payload[:note_id],
    new_title: payload[:new_title]
  )
end

if Rails.env.development? || Rails.env.test?
  DOMAIN_EVENTS.each do |event_name|
    ActiveSupport::Notifications.subscribe(event_name) do |name, _start, _finish, _id, payload|
      Rails.logger.debug { "[DomainEvent] #{name}: #{payload.inspect}" }
    end
  end
end
