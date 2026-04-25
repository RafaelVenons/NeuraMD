require "rails_helper"
require "mcp"

# Fase 4 do EPIC wikilink-roles — eager-load audit.
#
# Locks down the read-side of the role-aware NoteLink graph: serializers
# and MCP tools must NOT fan out into per-link N+1 queries when the
# backlink/outgoing-link counts grow. Without this guard the API
# response time scales linearly with link count instead of staying
# flat once the SELECT IN preload pays its one-time cost.
#
# Strategy: build a target note with N inbound + N outbound links, then
# call the read path twice (different N) and assert query count is
# constant within a small ceiling. Linear growth (count(2N) ≈ 2 × count(N))
# is what an N+1 looks like.
RSpec.describe "Wikilink roles — eager load audit" do
  def make_note(title)
    note = create(:note, title: title)
    rev = create(:note_revision, note: note, content_markdown: "body of #{title}")
    note.update_columns(head_revision_id: rev.id)
    note
  end

  def make_link(src:, dst:, role: nil)
    NoteLink.create!(
      src_note_id: src.id,
      dst_note_id: dst.id,
      hier_role: role,
      active: true,
      created_in_revision_id: src.head_revision_id
    )
  end

  describe Mcp::Tools::ReadNoteTool do
    it "does not N+1 on backlinks (constant queries as backlink count grows)" do
      target = make_note("Target")
      3.times { |i| make_link(src: make_note("Src #{i}"), dst: target) }

      baseline = QueryCounter.count { described_class.call(slug: target.slug) }

      target_big = make_note("TargetBig")
      30.times { |i| make_link(src: make_note("BigSrc #{i}"), dst: target_big) }

      scaled = QueryCounter.count { described_class.call(slug: target_big.slug) }

      # 10x the backlinks should not 10x the queries. Allow a tiny ceiling
      # for cache warmup variance, but reject linear growth.
      expect(scaled).to be <= baseline + 5
    end

    it "does not N+1 on outgoing links" do
      src = make_note("Src")
      3.times { |i| make_link(src: src, dst: make_note("Dst #{i}")) }

      baseline = QueryCounter.count { described_class.call(slug: src.slug) }

      src_big = make_note("SrcBig")
      30.times { |i| make_link(src: src_big, dst: make_note("BigDst #{i}")) }

      scaled = QueryCounter.count { described_class.call(slug: src_big.slug) }

      expect(scaled).to be <= baseline + 5
    end

    it "round-trips both source_slug and source_title for every backlink (smoke for missing eager load)" do
      target = make_note("RoundTrip")
      sources = 5.times.map { |i| make_note("Source #{i}").tap { |s| make_link(src: s, dst: target) } }

      response = described_class.call(slug: target.slug)
      data = JSON.parse(response.content.first[:text])

      slugs = data["backlinks"].map { |b| b["source_slug"] }.sort
      titles = data["backlinks"].map { |b| b["source_title"] }.sort
      expect(slugs).to eq(sources.map(&:slug).sort)
      expect(titles).to eq(sources.map(&:title).sort)
    end
  end

  describe Mcp::Tools::NoteGraphTool do
    it "does not N+1 on outgoing or incoming links" do
      hub = make_note("Hub")
      3.times { |i| make_link(src: hub, dst: make_note("HubDst #{i}")) }
      3.times { |i| make_link(src: make_note("HubSrc #{i}"), dst: hub) }

      baseline = QueryCounter.count { described_class.call(slug: hub.slug) }

      hub_big = make_note("HubBig")
      20.times { |i| make_link(src: hub_big, dst: make_note("HubBigDst #{i}")) }
      20.times { |i| make_link(src: make_note("HubBigSrc #{i}"), dst: hub_big) }

      scaled = QueryCounter.count { described_class.call(slug: hub_big.slug) }
      expect(scaled).to be <= baseline + 5
    end
  end

  describe Mcp::Tools::FindAnemicNotesTool do
    it "does not N+1 on suggested merge targets across many anemic notes" do
      # 3 anemic notes, each with a parent link
      3.times do |i|
        anemic = create(:note, title: "Anemic #{i}")
        rev = create(:note_revision, note: anemic, content_markdown: "x")
        anemic.update_columns(head_revision_id: rev.id)
        parent = make_note("Parent #{i}")
        make_link(src: anemic, dst: parent, role: "target_is_parent")
      end

      baseline = QueryCounter.count { described_class.call(max_lines: 10, limit: 50) }

      # Scale to 20 anemic notes — query count should NOT grow ~20x.
      20.times do |i|
        anemic = create(:note, title: "Anemic Big #{i}")
        rev = create(:note_revision, note: anemic, content_markdown: "x")
        anemic.update_columns(head_revision_id: rev.id)
        parent = make_note("Parent Big #{i}")
        make_link(src: anemic, dst: parent, role: "target_is_parent")
      end

      scaled = QueryCounter.count { described_class.call(max_lines: 10, limit: 50) }

      # 6x more anemic notes; queries should stay near constant. Ceiling is
      # generous to absorb the second-pass tag/property load but firmly
      # rejects per-note find_by + dst_note pairs.
      expect(scaled - baseline).to be <= 10
    end

    it "still surfaces the same merge target after the eager load fix" do
      anemic = create(:note, title: "Anemic Spec")
      rev = create(:note_revision, note: anemic, content_markdown: "x")
      anemic.update_columns(head_revision_id: rev.id)
      parent = make_note("Parent Spec")
      make_link(src: anemic, dst: parent, role: "target_is_parent")

      response = described_class.call(max_lines: 10, limit: 50)
      data = JSON.parse(response.content.first[:text])
      entry = data["anemic_notes"].find { |n| n["slug"] == anemic.slug }

      expect(entry).not_to be_nil
      expect(entry["merge_target"]).to include(
        "slug" => parent.slug, "title" => parent.title, "relation" => "parent"
      )
    end
  end
end
