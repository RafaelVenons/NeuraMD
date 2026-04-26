require "spec_helper"
# Force RAILS_ENV=test even if the parent shell exports development.
# A prior TentacleRuntime revision leaked RAILS_ENV=development into child
# shells; rspec then ran against the dev DB and DatabaseCleaner.clean_with(
# :truncation) wiped the user's acervo.
ENV["RAILS_ENV"] = "test"

# Defense against spawn-env leak when rspec runs inside a live tentacle:
# AGENT_S2S_TOKEN is inherited from the neuramd-web Puma unit, and
# NEURAMD_AGENT_SLUG/UUID/NEURAMD_TENTACLE_ID are injected by
# TentacleRuntime::Session#build_child_env. With those present, the
# Api::S2S::BaseController#configured_token (and the matching MCP tool)
# pick the env-first branch instead of the credentials fallback the S2S
# specs stub, and tests fail under a populated production token. CI runs
# without the spawn env so this is a no-op there; bin/rspec-airch ssh's
# to AIrch which doesn't forward env. The breakage shows up only for
# `bundle exec rspec` invoked from inside a tentacle session.
%w[AGENT_S2S_TOKEN NEURAMD_AGENT_SLUG NEURAMD_AGENT_UUID NEURAMD_TENTACLE_ID].each do |k|
  ENV.delete(k)
end

require_relative "../config/environment"
abort("The Rails environment is running in production mode!") if Rails.env.production?
unless Rails.env.test?
  abort("rails_helper refused to boot: Rails.env=#{Rails.env.inspect}, expected 'test'")
end
require "rspec/rails"
require "active_job/test_helper"
require "active_support/testing/time_helpers"
require "turbo/broadcastable/test_helper"
require "warden/test/helpers"

Rails.root.glob("spec/support/**/*.rb").sort_by(&:to_s).each { |f| require f }

# Tentacles::BootConfig defaults allowed_cwd_prefixes to /home/venom/projects/
# (the operator's workstation layout). On CI the runner user is `runner` and
# cannot create or canonicalize paths under /home/venom, so tests that
# resolve Tentacles::BootConfig.allowed_cwd_prefixes.first (+ fixture mkdir)
# fail with EACCES. Point the test suite at a writable tmpdir unless the
# operator has overridden it deliberately.
ENV["NEURAMD_TENTACLE_CWD_ROOTS"] ||= begin
  dir = Dir.mktmpdir("neuramd-tentacle-cwd-roots-")
  at_exit { FileUtils.remove_entry(dir) if File.directory?(dir) }
  "#{dir}/"
end

begin
  ActiveRecord::Migration.maintain_test_schema!
rescue ActiveRecord::PendingMigrationError => e
  abort e.to_s.strip
end

RSpec.configure do |config|
  config.fixture_paths = [Rails.root.join("spec/fixtures")]
  config.use_transactional_fixtures = false
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!

  config.include FactoryBot::Syntax::Methods
  config.include ActiveJob::TestHelper
  config.include ActiveSupport::Testing::TimeHelpers
  config.include Turbo::Broadcastable::TestHelper, type: :model
  config.include Devise::Test::IntegrationHelpers, type: :request
  config.include Devise::Test::ControllerHelpers, type: :controller
  config.include Warden::Test::Helpers, type: :system

  config.before(:suite) do
    DatabaseCleaner.clean_with(:truncation)
  end

  # System specs use truncation so the browser thread sees committed rows.
  # :dtach_integration specs exercise a real reader thread that writes to
  # TentacleSession on a separate AR connection — truncation makes those
  # writes visible from the main thread so the assertions can see them.
  # All other specs use the faster transaction rollback strategy.
  config.before(:each) do |example|
    DatabaseCleaner.strategy = if example.metadata[:dtach_integration] || example.metadata[:type] == :system
      :truncation
    else
      :transaction
    end
    DatabaseCleaner.start
  end

  config.before(:each, :dtach_integration) do
    unless Tentacles::DtachWrapper.dtach_on_path?
      skip "dtach binary not installed (run `sudo pacman -S dtach` or `sudo apt-get install -y dtach`)"
    end
  end

  config.after(:each) do |example|
    DatabaseCleaner.clean
    clear_enqueued_jobs
    clear_performed_jobs
    travel_back
    Warden.test_reset! if example.metadata[:type] == :system && Warden.respond_to?(:test_reset!)
  end

  # Registered AFTER the generic DatabaseCleaner.clean hook above so that
  # RSpec's LIFO after-hook ordering runs this FIRST — reader threads
  # spawned by TentacleRuntime.start write to TentacleSession on separate
  # AR connections, and truncating the table while those writes are in
  # flight causes flakes. Tear the runtime down first, let threads drain,
  # then let the generic hook truncate.
  config.after(:each, :dtach_integration) do
    TentacleRuntime.reset!
    # reset! joins reader threads with a short timeout (<=0.3s). Give
    # stragglers a final window to land their AR updates before the
    # truncation hook fires.
    sleep 0.1
  end

  config.before(:each) do
    ActiveJob::Base.queue_adapter = :test
  end
end

Shoulda::Matchers.configure do |config|
  config.integrate do |with|
    with.test_framework :rspec
    with.library :rails
  end
end
