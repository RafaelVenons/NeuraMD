require "rails_helper"
require "mcp"

RSpec.describe Mcp::Tools::SpawnChildTentacleTool do
  it "has correct tool metadata" do
    expect(described_class.name_value).to eq("spawn_child_tentacle")
    expect(described_class.description_value).to be_present
  end

  describe ".call" do
    let!(:parent) { create(:note, :with_head_revision, title: "Parent Tentacle") }

    it "creates a child note linked to the parent and returns metadata" do
      response = described_class.call(parent_slug: parent.slug, title: "New Child")
      data = JSON.parse(response.content.first[:text])

      expect(data["spawned"]).to be true
      expect(data["parent_slug"]).to eq(parent.slug)
      expect(data["tentacle_url"]).to eq("/notes/#{data["slug"]}/tentacle")

      child = Note.find(data["id"])
      expect(child.title).to eq("New Child")
      expect(child.head_revision.content_markdown).to include("[[Parent Tentacle|f:#{parent.id}]]")
      expect(child.head_revision.content_markdown).to include("## Todos")
      expect(child.tags.pluck(:name)).to include("tentacle")
    end

    it "creates an outgoing father link to the parent" do
      response = described_class.call(parent_slug: parent.slug, title: "Linked Child")
      data = JSON.parse(response.content.first[:text])
      child = Note.find(data["id"])

      link = child.outgoing_links.first
      expect(link.dst_note_id).to eq(parent.id)
      expect(link.hier_role).to eq("target_is_parent")
    end

    it "embeds the optional description between link and Todos heading" do
      response = described_class.call(
        parent_slug: parent.slug,
        title: "With Desc",
        description: "Investigate the data export pipeline."
      )
      data = JSON.parse(response.content.first[:text])
      body = Note.find(data["id"]).head_revision.content_markdown

      expect(body).to match(/\[\[Parent Tentacle\|f:.*\]\]\s+Investigate the data export pipeline\.\s+## Todos/m)
    end

    it "applies extra tags alongside tentacle" do
      response = described_class.call(
        parent_slug: parent.slug,
        title: "Tagged",
        extra_tags: "research, urgent"
      )
      data = JSON.parse(response.content.first[:text])

      expect(data["tags"]).to include("tentacle", "research", "urgent")
    end

    it "returns error when parent does not exist" do
      response = described_class.call(parent_slug: "missing", title: "Orphan")
      expect(response.error?).to be true
      expect(response.content.first[:text]).to include("Parent note not found")
    end

    it "returns error when title is blank" do
      response = described_class.call(parent_slug: parent.slug, title: "   ")
      expect(response.error?).to be true
      expect(response.content.first[:text]).to include("Title")
    end

    context "with agent boot config (cwd + initial_prompt)" do
      before do
        PropertyDefinition.find_or_create_by!(key: "tentacle_cwd") do |d|
          d.value_type = "text"
          d.system = true
          d.label = "Diretório de trabalho"
        end
        PropertyDefinition.find_or_create_by!(key: "tentacle_initial_prompt") do |d|
          d.value_type = "long_text"
          d.system = true
          d.label = "Prompt inicial"
        end
      end

      let(:allowed_dir) do
        path = described_class.cwd_allowed_prefixes.first + "maple-test-dir"
        FileUtils.mkdir_p(path)
        path
      end

      after { FileUtils.remove_entry(allowed_dir) if File.directory?(allowed_dir) }

      it "persists tentacle_cwd and tentacle_initial_prompt as properties" do
        response = described_class.call(
          parent_slug: parent.slug,
          title: "Dev Maple Session",
          cwd: allowed_dir,
          initial_prompt: "Você é Dev Maple. Leia o charter na nota."
        )
        data = JSON.parse(response.content.first[:text])
        child = Note.find(data["id"])

        expect(child.head_revision.properties_data["tentacle_cwd"]).to eq(allowed_dir)
        expect(child.head_revision.properties_data["tentacle_initial_prompt"])
          .to eq("Você é Dev Maple. Leia o charter na nota.")
      end

      it "rejects cwd outside the allowed prefixes" do
        response = described_class.call(
          parent_slug: parent.slug,
          title: "Escape Attempt",
          cwd: "/etc"
        )
        expect(response.error?).to be true
        expect(response.content.first[:text]).to include("cwd")
      end

      it "rejects cwd that is not an existing directory" do
        response = described_class.call(
          parent_slug: parent.slug,
          title: "Missing Dir",
          cwd: described_class.cwd_allowed_prefixes.first + "does-not-exist-#{SecureRandom.hex(4)}"
        )
        expect(response.error?).to be true
        expect(response.content.first[:text]).to include("cwd")
      end

      it "rejects cwd with .. segments that resolve outside the whitelist" do
        escape_path = described_class.cwd_allowed_prefixes.first + "../../../etc"
        response = described_class.call(
          parent_slug: parent.slug,
          title: "Dotdot Escape",
          cwd: escape_path
        )
        expect(response.error?).to be true
        expect(response.content.first[:text]).to include("cwd")
      end

      it "rejects cwd that is a symlink pointing outside the whitelist" do
        outside_target = Dir.mktmpdir
        symlink_path = described_class.cwd_allowed_prefixes.first + "maple-symlink-#{SecureRandom.hex(4)}"
        File.symlink(outside_target, symlink_path)

        response = described_class.call(
          parent_slug: parent.slug,
          title: "Symlink Escape",
          cwd: symlink_path
        )
        expect(response.error?).to be true
        expect(response.content.first[:text]).to include("cwd")
      ensure
        File.unlink(symlink_path) if symlink_path && File.symlink?(symlink_path)
        FileUtils.remove_entry(outside_target) if outside_target && File.directory?(outside_target)
      end

      it "persists the canonical path when cwd contains resolvable segments" do
        nested = File.join(allowed_dir, "nested")
        FileUtils.mkdir_p(nested)
        indirect = File.join(nested, "..")

        response = described_class.call(
          parent_slug: parent.slug,
          title: "Canonicalized",
          cwd: indirect
        )
        data = JSON.parse(response.content.first[:text])
        child = Note.find(data["id"])

        expect(child.head_revision.properties_data["tentacle_cwd"]).to eq(allowed_dir)
      end

      it "rejects initial_prompt larger than 2KB" do
        response = described_class.call(
          parent_slug: parent.slug,
          title: "Chatty",
          initial_prompt: "a" * 2049
        )
        expect(response.error?).to be true
        expect(response.content.first[:text]).to include("initial_prompt")
      end

      it "accepts initial_prompt alone without cwd" do
        response = described_class.call(
          parent_slug: parent.slug,
          title: "Prompt Only",
          initial_prompt: "boot message"
        )
        data = JSON.parse(response.content.first[:text])
        child = Note.find(data["id"])

        expect(child.head_revision.properties_data["tentacle_initial_prompt"]).to eq("boot message")
        expect(child.head_revision.properties_data["tentacle_cwd"]).to be_nil
      end
    end
  end
end
