module QueryCounter
  IGNORED_NAMES = ["SCHEMA", "TRANSACTION", "CACHE"].freeze

  # Returns the SQL queries (excluding schema/cache/transaction noise)
  # executed during the block. Lets specs assert on absolute counts so
  # eager-load regressions can be caught deterministically — without
  # depending on the bullet gem (not in the bundle).
  def self.capture(&block)
    queries = []
    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |_name, _start, _finish, _id, payload|
      next if IGNORED_NAMES.include?(payload[:name])
      next if payload[:sql].to_s.match?(/^\s*(BEGIN|COMMIT|ROLLBACK|RELEASE|SAVEPOINT)/i)
      queries << payload[:sql]
    end
    block.call
    queries
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
  end

  def self.count(&block)
    capture(&block).size
  end
end
