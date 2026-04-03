require "rails_helper"

RSpec.describe Search::Dsl::Executor do
  let(:user) { create(:user) }

  def create_note_with_content(title:, content: "Conteudo de #{title}", **attrs)
    note = create(:note, title: title, **attrs)
    Notes::CheckpointService.call(note: note, content: content, author: user)
    note.reload
  end

  def base_scope
    Note.active
      .where.not(head_revision_id: nil)
      .joins("LEFT JOIN note_revisions search_revisions ON search_revisions.id = notes.head_revision_id")
      .group("notes.id, search_revisions.id")
  end

  def token(operator, value)
    Search::Dsl::Token.new(operator: operator, value: value, raw: "#{operator}:#{value}", position: 0)
  end

  describe "tag operator" do
    it "filters notes by tag" do
      tagged = create_note_with_content(title: "Tagged Note")
      other = create_note_with_content(title: "Other Note")
      tag = create(:tag, name: "neurociencia")
      NoteTag.create!(note: tagged, tag: tag)

      result = described_class.call(scope: base_scope, tokens: [token(:tag, "neurociencia")])
      expect(result.pluck(:id)).to include(tagged.id)
      expect(result.pluck(:id)).not_to include(other.id)
    end

    it "is case-insensitive via downcase" do
      note = create_note_with_content(title: "Note")
      tag = create(:tag, name: "neuro")
      NoteTag.create!(note: note, tag: tag)

      result = described_class.call(scope: base_scope, tokens: [token(:tag, "Neuro")])
      expect(result.pluck(:id)).to include(note.id)
    end
  end

  describe "alias operator" do
    it "filters notes by alias (case-insensitive)" do
      note = create_note_with_content(title: "Dopamina")
      create(:note_alias, note: note, name: "DP")
      other = create_note_with_content(title: "Serotonina")

      result = described_class.call(scope: base_scope, tokens: [token(:alias, "dp")])
      expect(result.pluck(:id)).to include(note.id)
      expect(result.pluck(:id)).not_to include(other.id)
    end
  end

  describe "prop operator" do
    it "filters by JSONB property" do
      note = create_note_with_content(title: "Done Note")
      note.head_revision.update!(properties_data: {"status" => "done"})
      other = create_note_with_content(title: "Draft Note")
      other.head_revision.update!(properties_data: {"status" => "draft"})

      result = described_class.call(scope: base_scope, tokens: [token(:prop, "status=done")])
      expect(result.pluck(:id)).to include(note.id)
      expect(result.pluck(:id)).not_to include(other.id)
    end
  end

  describe "kind operator (sugar for prop:kind=X)" do
    it "filters by kind property" do
      note = create_note_with_content(title: "Reference Note")
      note.head_revision.update!(properties_data: {"kind" => "reference"})
      other = create_note_with_content(title: "Journal Note")
      other.head_revision.update!(properties_data: {"kind" => "journal"})

      result = described_class.call(scope: base_scope, tokens: [token(:kind, "reference")])
      expect(result.pluck(:id)).to include(note.id)
      expect(result.pluck(:id)).not_to include(other.id)
    end
  end

  describe "status operator (sugar for prop:status=X)" do
    it "filters by status property" do
      note = create_note_with_content(title: "Draft")
      note.head_revision.update!(properties_data: {"status" => "draft"})
      other = create_note_with_content(title: "Published")
      other.head_revision.update!(properties_data: {"status" => "published"})

      result = described_class.call(scope: base_scope, tokens: [token(:status, "draft")])
      expect(result.pluck(:id)).to include(note.id)
      expect(result.pluck(:id)).not_to include(other.id)
    end
  end

  describe "has operator" do
    it "filters notes with assets" do
      with_asset = create_note_with_content(title: "With Asset")
      with_asset.head_revision.assets.attach(
        io: StringIO.new("test"), filename: "test.txt", content_type: "text/plain"
      )
      without_asset = create_note_with_content(title: "Without Asset")

      result = described_class.call(scope: base_scope, tokens: [token(:has, "asset")])
      expect(result.pluck(:id)).to include(with_asset.id)
      expect(result.pluck(:id)).not_to include(without_asset.id)
    end
  end

  describe "link operator" do
    it "finds notes that link TO a target note" do
      target = create_note_with_content(title: "Alvo")
      source = create_note_with_content(title: "Fonte")
      bystander = create_note_with_content(title: "Bystander")
      create(:note_link, src_note: source, dst_note: target, active: true)

      result = described_class.call(scope: base_scope, tokens: [token(:link, "Alvo")])
      expect(result.pluck(:id)).to include(source.id)
      expect(result.pluck(:id)).not_to include(bystander.id)
      expect(result.pluck(:id)).not_to include(target.id)
    end
  end

  describe "linkedfrom operator" do
    it "finds notes linked FROM a source note" do
      source = create_note_with_content(title: "Origem")
      target = create_note_with_content(title: "Destino")
      bystander = create_note_with_content(title: "Bystander")
      create(:note_link, src_note: source, dst_note: target, active: true)

      result = described_class.call(scope: base_scope, tokens: [token(:linkedfrom, "Origem")])
      expect(result.pluck(:id)).to include(target.id)
      expect(result.pluck(:id)).not_to include(bystander.id)
      expect(result.pluck(:id)).not_to include(source.id)
    end
  end

  describe "orphan operator" do
    it "finds notes with no active links in or out" do
      orphan = create_note_with_content(title: "Orphan")
      connected = create_note_with_content(title: "Connected")
      other = create_note_with_content(title: "Other")
      create(:note_link, src_note: connected, dst_note: other, active: true)

      result = described_class.call(scope: base_scope, tokens: [token(:orphan, "true")])
      expect(result.pluck(:id)).to include(orphan.id)
      expect(result.pluck(:id)).not_to include(connected.id)
      expect(result.pluck(:id)).not_to include(other.id)
    end
  end

  describe "deadend operator" do
    it "finds notes with no active outgoing links" do
      deadend = create_note_with_content(title: "Deadend")
      linked = create_note_with_content(title: "Linked")
      target = create_note_with_content(title: "Target")
      create(:note_link, src_note: linked, dst_note: target, active: true)

      result = described_class.call(scope: base_scope, tokens: [token(:deadend, "true")])
      # deadend and target have no outgoing links
      ids = result.pluck(:id)
      expect(ids).to include(deadend.id)
      expect(ids).to include(target.id)
      expect(ids).not_to include(linked.id)
    end
  end

  describe "created operator" do
    it "filters by creation date" do
      old = create_note_with_content(title: "Old Note")
      old.update_column(:created_at, 2.years.ago)
      recent = create_note_with_content(title: "Recent Note")

      result = described_class.call(scope: base_scope, tokens: [token(:created, ">30d")])
      expect(result.pluck(:id)).to include(recent.id)
      expect(result.pluck(:id)).not_to include(old.id)
    end
  end

  describe "updated operator" do
    it "filters by update date" do
      stale = create_note_with_content(title: "Stale Note")
      stale.update_column(:updated_at, 60.days.ago)
      fresh = create_note_with_content(title: "Fresh Note")

      result = described_class.call(scope: base_scope, tokens: [token(:updated, ">7d")])
      expect(result.pluck(:id)).to include(fresh.id)
      expect(result.pluck(:id)).not_to include(stale.id)
    end
  end

  describe "composition" do
    it "applies multiple filters with AND logic" do
      tag = create(:tag, name: "neuro")
      both = create_note_with_content(title: "Both Match")
      both.head_revision.update!(properties_data: {"status" => "draft"})
      NoteTag.create!(note: both, tag: tag)

      tag_only = create_note_with_content(title: "Tag Only")
      NoteTag.create!(note: tag_only, tag: tag)
      tag_only.head_revision.update!(properties_data: {"status" => "done"})

      result = described_class.call(
        scope: base_scope,
        tokens: [token(:tag, "neuro"), token(:status, "draft")]
      )
      expect(result.pluck(:id)).to include(both.id)
      expect(result.pluck(:id)).not_to include(tag_only.id)
    end
  end
end
