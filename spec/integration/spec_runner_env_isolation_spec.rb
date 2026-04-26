require "rails_helper"

# Locks down the rails_helper.rb defensive scrub of tentacle-spawn env
# vars. When `bundle exec rspec` runs inside a live tentacle session,
# AGENT_S2S_TOKEN (inherited from the neuramd-web Puma unit) and
# NEURAMD_AGENT_SLUG/UUID/NEURAMD_TENTACLE_ID (injected by
# TentacleRuntime::Session#build_child_env) leak into the spec process.
# Without the scrub, Api::S2S::BaseController#configured_token picks the
# env-first branch and the S2S request specs that stub credentials see
# the production token instead of the test fixture token.
#
# This spec is a contract assertion: if someone removes the scrub, this
# fails immediately on the first tentacle-local rspec run rather than
# silently breaking S2S specs with confusing 401s.
RSpec.describe "spec runner env isolation" do
  describe "tentacle-spawn vars" do
    %w[AGENT_S2S_TOKEN NEURAMD_AGENT_SLUG NEURAMD_AGENT_UUID NEURAMD_TENTACLE_ID].each do |var|
      it "ENV[#{var.inspect}] is unset (scrubbed by rails_helper)" do
        expect(ENV[var]).to be_nil
      end
    end
  end
end
