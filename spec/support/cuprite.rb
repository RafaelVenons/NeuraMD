require "capybara/cuprite"

# Headless Chrome via Cuprite (Chrome DevTools Protocol — no ChromeDriver needed).
# Set HEADED=1 to open a real browser window for debugging.
Capybara.register_driver(:cuprite) do |app|
  Capybara::Cuprite::Driver.new(app, {
    browser_options: { "no-sandbox": nil, "disable-gpu": nil },
    headless: ENV["HEADED"] != "1",
    window_size: [1400, 900],
    process_timeout: 30,
    timeout: 10,
    js_errors: true,   # raises on uncaught JS errors
    pending_connection_errors: false
  })
end

Capybara.default_driver    = :rack_test   # fast for non-JS specs
Capybara.javascript_driver = :cuprite     # real browser for JS specs

RSpec.configure do |config|
  config.before(:each, type: :system) do
    driven_by :cuprite
  end

  # Sign-in helper for system specs (works with Devise + Cuprite).
  config.include Warden::Test::Helpers, type: :system
  config.after(:each, type: :system) { Warden.test_reset! }
end
