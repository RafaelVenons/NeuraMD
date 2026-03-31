module DomainEvents
  extend ActiveSupport::Concern

  NAMESPACE = "neuramd"

  private

  def publish_event(name, payload = {})
    ActiveSupport::Notifications.instrument("#{NAMESPACE}.#{name}", payload)
  end

  class_methods do
    private

    def publish_event(name, payload = {})
      ActiveSupport::Notifications.instrument("#{NAMESPACE}.#{name}", payload)
    end
  end
end
