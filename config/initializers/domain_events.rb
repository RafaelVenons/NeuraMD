DOMAIN_EVENTS = %w[
  neuramd.note.created
  neuramd.note.updated
  neuramd.note.renamed
  neuramd.note.deleted
  neuramd.note.restored
  neuramd.link.created
  neuramd.link.deleted
  neuramd.property.changed
].freeze

if Rails.env.development? || Rails.env.test?
  DOMAIN_EVENTS.each do |event_name|
    ActiveSupport::Notifications.subscribe(event_name) do |name, _start, _finish, _id, payload|
      Rails.logger.debug { "[DomainEvent] #{name}: #{payload.inspect}" }
    end
  end
end
