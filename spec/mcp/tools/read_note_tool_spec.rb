require "rails_helper"
require "mcp"

RSpec.describe Mcp::Tools::ReadNoteTool do
  let!(:note) { create(:note, :with_head_revision, title: "Nota de teste") }

  it "has correct tool metadata" do
    expect(described_class.name_value).to eq("read_note")
    expect(described_class.description_value).to be_present
  end

  it "reads a note by slug" do
    response = described_class.call(slug: note.slug)
    content = JSON.parse(response.content.first[:text])

    expect(content["title"]).to eq("Nota de teste")
    expect(content["slug"]).to eq(note.slug)
    expect(content).to have_key("body")
    expect(content).to have_key("tags")
    expect(content).to have_key("links")
    expect(content).to have_key("created_at")
    expect(content).to have_key("updated_at")
  end

  it "includes tags in the response" do
    tag = create(:tag, name: "new-specs")
    note.tags << tag

    response = described_class.call(slug: note.slug)
    content = JSON.parse(response.content.first[:text])
    expect(content["tags"]).to include("new-specs")
  end

  it "includes outgoing links in the response" do
    target = create(:note, :with_head_revision, title: "Target note")
    revision = note.head_revision
    create(:note_link, src_note: note, dst_note: target, created_in_revision: revision)

    response = described_class.call(slug: note.slug)
    content = JSON.parse(response.content.first[:text])
    expect(content["links"].length).to eq(1)
    expect(content["links"].first["target_title"]).to eq("Target note")
    expect(content["links"].first["direction"]).to eq("outgoing")
  end

  it "includes backlinks (incoming links) in the response" do
    source = create(:note, :with_head_revision, title: "Nota que referencia")
    create(:note_link, src_note: source, dst_note: note,
      hier_role: "target_is_child",
      created_in_revision: source.head_revision)

    response = described_class.call(slug: note.slug)
    content = JSON.parse(response.content.first[:text])
    expect(content["backlinks"].length).to eq(1)
    expect(content["backlinks"].first["source_title"]).to eq("Nota que referencia")
    expect(content["backlinks"].first["role"]).to eq("target_is_child")
    expect(content["backlinks"].first["role_token"]).to eq("c")
    expect(content["backlinks"].first["direction"]).to eq("incoming")
  end

  describe "role_token additive field (Fase 3)" do
    let!(:center) { create(:note, :with_head_revision, title: "Centro") }

    it "preserves semantic role and adds role_token for outgoing links" do
      dst = create(:note, :with_head_revision, title: "Alvo")
      create(:note_link,
        src_note: center, dst_note: dst,
        hier_role: "target_is_parent",
        created_in_revision: center.head_revision)

      response = described_class.call(slug: center.slug)
      content = JSON.parse(response.content.first[:text])
      expect(content["links"].first["role"]).to eq("target_is_parent")
      expect(content["links"].first["role_token"]).to eq("f")
    end

    it "emits null role and null role_token for plain links without hier_role" do
      dst = create(:note, :with_head_revision, title: "Plain")
      create(:note_link,
        src_note: center, dst_note: dst,
        hier_role: nil,
        created_in_revision: center.head_revision)

      response = described_class.call(slug: center.slug)
      content = JSON.parse(response.content.first[:text])
      expect(content["links"].first).to have_key("role")
      expect(content["links"].first).to have_key("role_token")
      expect(content["links"].first["role"]).to be_nil
      expect(content["links"].first["role_token"]).to be_nil
    end

    it "maps all delegation tokens (p/d/v/x) in backlinks role_token while role stays semantic" do
      mapping = {
        "delegation_pending" => "p",
        "delegation_directive" => "d",
        "delegation_verify" => "v",
        "delegation_block" => "x"
      }
      mapping.each do |semantic, _token|
        src = create(:note, :with_head_revision, title: "src-#{semantic}")
        create(:note_link,
          src_note: src, dst_note: center,
          hier_role: semantic,
          created_in_revision: src.head_revision)
      end

      response = described_class.call(slug: center.slug)
      content = JSON.parse(response.content.first[:text])
      tokens = content["backlinks"].map { |b| b["role_token"] }.sort
      roles = content["backlinks"].map { |b| b["role"] }.sort
      expect(tokens).to eq(%w[d p v x])
      expect(roles).to eq(%w[delegation_block delegation_directive delegation_pending delegation_verify])
    end
  end

  describe "backlink filtering (Fase 3)" do
    let!(:center) { create(:note, :with_head_revision, title: "Centro") }

    def add_backlink(title:, hier_role:, updated_at: nil)
      src = create(:note, :with_head_revision, title: title)
      link = create(:note_link,
        src_note: src, dst_note: center,
        hier_role: hier_role,
        created_in_revision: src.head_revision)
      link.update_columns(updated_at: updated_at) if updated_at
      link
    end

    it "filters backlinks by role token CSV (backlink_roles)" do
      add_backlink(title: "pend", hier_role: "delegation_pending")
      add_backlink(title: "block", hier_role: "delegation_block")
      add_backlink(title: "parent", hier_role: "target_is_parent")

      response = described_class.call(slug: center.slug, backlink_roles: "p,x")
      content = JSON.parse(response.content.first[:text])
      tokens = content["backlinks"].map { |b| b["role_token"] }.sort
      expect(tokens).to eq(%w[p x])
    end

    it "filters to plain links when backlink_roles contains 'none'" do
      add_backlink(title: "pend", hier_role: "delegation_pending")
      add_backlink(title: "plain", hier_role: nil)

      response = described_class.call(slug: center.slug, backlink_roles: "none")
      content = JSON.parse(response.content.first[:text])
      expect(content["backlinks"].length).to eq(1)
      expect(content["backlinks"].first["source_title"]).to eq("plain")
      expect(content["backlinks"].first["role"]).to be_nil
      expect(content["backlinks"].first["role_token"]).to be_nil
    end

    it "filters by backlinks_updated_since (ISO8601)" do
      old = add_backlink(title: "old", hier_role: "delegation_pending",
        updated_at: 2.days.ago)
      _new = add_backlink(title: "new", hier_role: "delegation_pending")

      response = described_class.call(slug: center.slug,
        backlinks_updated_since: 1.day.ago.iso8601)
      content = JSON.parse(response.content.first[:text])
      titles = content["backlinks"].map { |b| b["source_title"] }
      expect(titles).to eq(["new"])
      expect(titles).not_to include(old.src_note.title)
    end
  end

  describe "backlink pagination (Fase 3)" do
    let!(:center) { create(:note, :with_head_revision, title: "Centro") }

    before do
      # 5 backlinks, different updated_at for determinism
      5.times do |i|
        src = create(:note, :with_head_revision, title: "src-#{i}")
        link = create(:note_link,
          src_note: src, dst_note: center,
          hier_role: "delegation_pending",
          created_in_revision: src.head_revision)
        link.update_columns(updated_at: Time.current - i.minutes)
      end
    end

    it "defaults limit to 100 and reports has_more=false when fits" do
      response = described_class.call(slug: center.slug)
      content = JSON.parse(response.content.first[:text])
      expect(content["backlinks"].length).to eq(5)
      expect(content).to have_key("backlinks_next_cursor")
      expect(content["backlinks_next_cursor"]).to be_nil
      expect(content["backlinks_has_more"]).to eq(false)
    end

    it "honors smaller backlink_limit and emits cursor" do
      response = described_class.call(slug: center.slug, backlink_limit: 2)
      content = JSON.parse(response.content.first[:text])
      expect(content["backlinks"].length).to eq(2)
      expect(content["backlinks_has_more"]).to eq(true)
      expect(content["backlinks_next_cursor"]).to be_a(String)
    end

    it "resumes pagination with cursor, deterministic ordering" do
      first = described_class.call(slug: center.slug, backlink_limit: 2)
      first_body = JSON.parse(first.content.first[:text])
      cursor = first_body["backlinks_next_cursor"]

      second = described_class.call(slug: center.slug,
        backlink_limit: 2, backlink_cursor: cursor)
      second_body = JSON.parse(second.content.first[:text])
      expect(second_body["backlinks"].length).to eq(2)
      expect(second_body["backlinks_has_more"]).to eq(true)

      third = described_class.call(slug: center.slug,
        backlink_limit: 2, backlink_cursor: second_body["backlinks_next_cursor"])
      third_body = JSON.parse(third.content.first[:text])
      expect(third_body["backlinks"].length).to eq(1)
      expect(third_body["backlinks_has_more"]).to eq(false)
      expect(third_body["backlinks_next_cursor"]).to be_nil

      seen_titles = first_body["backlinks"].map { |b| b["source_title"] } +
                    second_body["backlinks"].map { |b| b["source_title"] } +
                    third_body["backlinks"].map { |b| b["source_title"] }
      expect(seen_titles.uniq.length).to eq(5)
    end

    it "clamps backlink_limit at 200 silently" do
      response = described_class.call(slug: center.slug, backlink_limit: 10_000)
      expect(response.error?).to be_falsey
      content = JSON.parse(response.content.first[:text])
      expect(content["backlinks"].length).to eq(5)
    end

    it "returns error for malformed cursor" do
      response = described_class.call(slug: center.slug,
        backlink_cursor: "not-base64!!!")
      expect(response.error?).to be true
    end
  end

  it "follows slug redirects" do
    create(:slug_redirect, note: note, slug: "old-slug")

    response = described_class.call(slug: "old-slug")
    content = JSON.parse(response.content.first[:text])
    expect(content["title"]).to eq("Nota de teste")
  end

  it "returns error for non-existent slug" do
    response = described_class.call(slug: "nao-existe")
    expect(response.error?).to be true
  end

  it "returns error for deleted note" do
    note.soft_delete!
    response = described_class.call(slug: note.slug)
    expect(response.error?).to be true
  end

  it "includes aliases in the response" do
    create(:note_alias, note: note, name: "Test Alias")
    response = described_class.call(slug: note.slug)
    content = JSON.parse(response.content.first[:text])
    expect(content["aliases"]).to eq(["Test Alias"])
  end

  it "finds note by alias" do
    create(:note_alias, note: note, name: "My Alias")
    response = described_class.call(slug: "My Alias")
    content = JSON.parse(response.content.first[:text])
    expect(content["title"]).to eq("Nota de teste")
  end

  it "includes headings in the response" do
    create(:note_heading, note: note, level: 1, text: "Introduction", slug: "introduction", position: 0)
    create(:note_heading, note: note, level: 2, text: "Details", slug: "details", position: 1)

    response = described_class.call(slug: note.slug)
    content = JSON.parse(response.content.first[:text])

    expect(content["headings"].length).to eq(2)
    expect(content["headings"].first).to eq({"text" => "Introduction", "slug" => "introduction", "level" => 1})
    expect(content["headings"].last).to eq({"text" => "Details", "slug" => "details", "level" => 2})
  end

  it "includes blocks in the response" do
    create(:note_block, note: note, block_id: "summary", content: "This is the summary", block_type: "paragraph", position: 0)
    create(:note_block, note: note, block_id: "key-point", content: "A key point", block_type: "list_item", position: 1)

    response = described_class.call(slug: note.slug)
    content = JSON.parse(response.content.first[:text])

    expect(content["blocks"].length).to eq(2)
    expect(content["blocks"].first).to eq({"block_id" => "summary", "content" => "This is the summary", "block_type" => "paragraph"})
    expect(content["blocks"].last).to eq({"block_id" => "key-point", "content" => "A key point", "block_type" => "list_item"})
  end
end
