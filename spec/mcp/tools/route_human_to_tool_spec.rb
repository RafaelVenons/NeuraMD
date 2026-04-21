require "rails_helper"
require "mcp"

RSpec.describe Mcp::Tools::RouteHumanToTool do
  let(:source_tentacle_id) { SecureRandom.uuid }
  let(:server_context) { {tentacle_id: source_tentacle_id} }

  before { allow(TentacleChannel).to receive(:broadcast_route_suggestion) }

  it "has correct tool metadata" do
    expect(described_class.name_value).to eq("route_human_to")
    expect(described_class.description_value).to be_present
  end

  describe ".call" do
    let!(:target) { create(:note, :with_head_revision, title: "Especialista NeuraMD") }

    it "broadcasts a route-suggestion on the caller tentacle stream" do
      described_class.call(
        target_slug: target.slug,
        suggested_prompt: "Implemente OAuth Discord baseado no Maple.",
        rationale: "Mudança estrutural de auth é escopo do Especialista.",
        server_context: server_context
      )

      expect(TentacleChannel).to have_received(:broadcast_route_suggestion).with(
        tentacle_id: source_tentacle_id,
        target_slug: target.slug,
        target_title: "Especialista NeuraMD",
        suggested_prompt: "Implemente OAuth Discord baseado no Maple.",
        rationale: "Mudança estrutural de auth é escopo do Especialista."
      )
    end

    it "returns a success payload with the routed target" do
      response = described_class.call(
        target_slug: target.slug,
        suggested_prompt: "Charter aqui",
        server_context: server_context
      )
      data = JSON.parse(response.content.first[:text])

      expect(data["routed"]).to be true
      expect(data["target_slug"]).to eq(target.slug)
      expect(data["target_title"]).to eq("Especialista NeuraMD")
    end

    it "accepts rationale being optional" do
      response = described_class.call(
        target_slug: target.slug,
        suggested_prompt: "x",
        server_context: server_context
      )
      expect(response.error?).to be false
      expect(TentacleChannel).to have_received(:broadcast_route_suggestion).with(
        hash_including(rationale: nil)
      )
    end

    it "uses the tentacle_id from server_context even if ENV is different" do
      ENV["NEURAMD_TENTACLE_ID"] = "leaked-from-env"
      described_class.call(
        target_slug: target.slug,
        suggested_prompt: "x",
        server_context: server_context
      )
      ENV.delete("NEURAMD_TENTACLE_ID")

      expect(TentacleChannel).to have_received(:broadcast_route_suggestion).with(
        hash_including(tentacle_id: source_tentacle_id)
      )
    end

    it "routes distinct callers to their own streams in sequence" do
      first = SecureRandom.uuid
      second = SecureRandom.uuid

      described_class.call(target_slug: target.slug, suggested_prompt: "first",
        server_context: {tentacle_id: first})
      described_class.call(target_slug: target.slug, suggested_prompt: "second",
        server_context: {tentacle_id: second})

      expect(TentacleChannel).to have_received(:broadcast_route_suggestion)
        .with(hash_including(tentacle_id: first, suggested_prompt: "first")).ordered
      expect(TentacleChannel).to have_received(:broadcast_route_suggestion)
        .with(hash_including(tentacle_id: second, suggested_prompt: "second")).ordered
    end

    it "errors when target note does not exist" do
      response = described_class.call(
        target_slug: "no-such-note",
        suggested_prompt: "x",
        server_context: server_context
      )
      expect(response.error?).to be true
      expect(response.content.first[:text]).to include("Target note not found")
      expect(TentacleChannel).not_to have_received(:broadcast_route_suggestion)
    end

    it "errors when suggested_prompt is blank" do
      response = described_class.call(
        target_slug: target.slug,
        suggested_prompt: "  ",
        server_context: server_context
      )
      expect(response.error?).to be true
      expect(response.content.first[:text]).to include("suggested_prompt")
      expect(TentacleChannel).not_to have_received(:broadcast_route_suggestion)
    end

    it "errors when suggested_prompt exceeds 2048 bytes" do
      response = described_class.call(
        target_slug: target.slug,
        suggested_prompt: "a" * 2049,
        server_context: server_context
      )
      expect(response.error?).to be true
      expect(response.content.first[:text]).to include("suggested_prompt")
    end

    it "errors when server_context has no tentacle_id" do
      response = described_class.call(
        target_slug: target.slug,
        suggested_prompt: "x",
        server_context: {}
      )
      expect(response.error?).to be true
      expect(response.content.first[:text]).to include("tentacle_id")
      expect(TentacleChannel).not_to have_received(:broadcast_route_suggestion)
    end

    it "errors when server_context is nil" do
      response = described_class.call(
        target_slug: target.slug,
        suggested_prompt: "x",
        server_context: nil
      )
      expect(response.error?).to be true
      expect(response.content.first[:text]).to include("tentacle_id")
    end
  end
end

RSpec.describe TentacleChannel, ".broadcast_route_suggestion" do
  it "broadcasts a route-suggestion message to the tentacle stream" do
    tentacle_id = SecureRandom.uuid
    expect(described_class).to receive(:broadcast_to).with(
      tentacle_id,
      hash_including(
        type: "route-suggestion",
        target: hash_including(slug: "especialista-neuramd", title: "Especialista NeuraMD"),
        suggested_prompt: "hello",
        rationale: "because"
      )
    )

    described_class.broadcast_route_suggestion(
      tentacle_id: tentacle_id,
      target_slug: "especialista-neuramd",
      target_title: "Especialista NeuraMD",
      suggested_prompt: "hello",
      rationale: "because"
    )
  end
end
