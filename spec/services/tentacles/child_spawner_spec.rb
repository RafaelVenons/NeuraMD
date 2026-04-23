require "rails_helper"

RSpec.describe Tentacles::ChildSpawner do
  let!(:parent) { create(:note, :with_head_revision, title: "Parent Hub") }

  describe ".call" do
    it "creates a child note with a checkpoint and the tentacle tag" do
      result = described_class.call(parent: parent, title: "First Child")

      expect(result.child).to be_persisted
      expect(result.child.title).to eq("First Child")
      expect(result.child.head_revision_id).to eq(result.revision.id)
      expect(result.child.head_revision.content_markdown).to include("[[Parent Hub|f:#{parent.id}]]")
      expect(result.child.head_revision.content_markdown).to include("## Todos")
      expect(result.child.tags.pluck(:name)).to include("tentacle")
    end

    it "creates a target_is_parent link back to the parent" do
      result = described_class.call(parent: parent, title: "Linked")
      link = result.child.outgoing_links.first

      expect(link).to be_present
      expect(link.dst_note_id).to eq(parent.id)
      expect(link.hier_role).to eq("target_is_parent")
    end

    it "inserts the description between the link and the Todos heading" do
      result = described_class.call(
        parent: parent,
        title: "With Desc",
        description: "Investigate export pipeline."
      )

      expect(result.body).to match(/\[\[Parent Hub\|f:.*\]\]\s+Investigate export pipeline\.\s+## Todos/m)
    end

    it "accepts extra comma-separated tags" do
      result = described_class.call(parent: parent, title: "Tagged", extra_tags: "research, urgent")
      expect(result.child.tags.pluck(:name)).to include("tentacle", "research", "urgent")
    end

    it "raises BlankTitle when title is empty" do
      expect {
        described_class.call(parent: parent, title: "   ")
      }.to raise_error(described_class::BlankTitle)
    end

    context "with agent boot config" do
      before do
        PropertyDefinition.find_or_create_by!(key: "tentacle_cwd") do |d|
          d.value_type = "text"
          d.system = true
        end
        PropertyDefinition.find_or_create_by!(key: "tentacle_initial_prompt") do |d|
          d.value_type = "long_text"
          d.system = true
        end
        PropertyDefinition.find_or_create_by!(key: "tentacle_workspace") do |d|
          d.value_type = "text"
          d.system = true
        end
      end

      it "sets tentacle_cwd and tentacle_initial_prompt on the head revision when provided" do
        result = described_class.call(
          parent: parent,
          title: "With Config",
          cwd: "/home/venom/projects/MapledaRapeize",
          initial_prompt: "boot me"
        )

        expect(result.child.head_revision.properties_data["tentacle_cwd"])
          .to eq("/home/venom/projects/MapledaRapeize")
        expect(result.child.head_revision.properties_data["tentacle_initial_prompt"])
          .to eq("boot me")
      end

      it "leaves properties empty when cwd and initial_prompt are nil" do
        result = described_class.call(parent: parent, title: "Bare")

        expect(result.child.head_revision.properties_data).to eq({})
      end

      it "only sets the keys that were provided" do
        result = described_class.call(
          parent: parent,
          title: "Prompt Only",
          initial_prompt: "only prompt"
        )

        expect(result.child.head_revision.properties_data).to eq(
          "tentacle_initial_prompt" => "only prompt"
        )
      end

      it "sets tentacle_workspace on the head revision when provided" do
        result = described_class.call(
          parent: parent,
          title: "With Workspace",
          workspace: "neuramd"
        )

        expect(result.child.head_revision.properties_data["tentacle_workspace"])
          .to eq("neuramd")
      end

      it "persists workspace alongside cwd and initial_prompt" do
        result = described_class.call(
          parent: parent,
          title: "All Three",
          cwd: "/home/venom/projects/MapledaRapeize",
          initial_prompt: "boot",
          workspace: "neuramd"
        )

        expect(result.child.head_revision.properties_data).to eq(
          "tentacle_cwd" => "/home/venom/projects/MapledaRapeize",
          "tentacle_initial_prompt" => "boot",
          "tentacle_workspace" => "neuramd"
        )
      end

      it "treats blank workspace as not-set" do
        result = described_class.call(parent: parent, title: "Blank WS", workspace: "")

        expect(result.child.head_revision.properties_data).not_to have_key("tentacle_workspace")
      end
    end
  end
end
