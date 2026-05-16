require "rails_helper"

RSpec.describe TentacleRuntime::Session, "wake-nudge tracking" do
  let(:tentacle_id) { create(:note).id }

  after { TentacleRuntime.reset! }

  def fresh_session
    TentacleRuntime.start(tentacle_id: tentacle_id, command: ["sleep", "5"])
  end

  it "reports not recently nudged before any nudge" do
    session = fresh_session
    expect(session.recently_wake_nudged?(within: 60)).to be false
  end

  it "reports recently nudged within the window after mark_wake_nudged!" do
    session = fresh_session
    session.mark_wake_nudged!
    expect(session.recently_wake_nudged?(within: 60)).to be true
  end

  it "reports not recently nudged once the window has elapsed" do
    session = fresh_session
    session.mark_wake_nudged!(at: 2.minutes.ago)
    expect(session.recently_wake_nudged?(within: 60)).to be false
  end
end
