require "rails_helper"

RSpec.describe Notes::RenameService, type: :service do
  let(:user) { create(:user) }
  let(:note) { create(:note, title: "Titulo Original") }

  describe ".call" do
    it "updates title and regenerates slug" do
      result = described_class.call(note: note, new_title: "Novo Titulo")
      expect(note.reload.title).to eq("Novo Titulo")
      expect(note.slug).to eq("novo-titulo")
      expect(result.slug_changed).to be true
    end

    it "creates a slug_redirect for the old slug" do
      old_slug = note.slug
      described_class.call(note: note, new_title: "Outro Nome")
      expect(SlugRedirect.find_by(slug: old_slug, note: note)).to be_present
    end

    it "handles slug collision by appending counter" do
      create(:note, title: "Destino")
      described_class.call(note: note, new_title: "Destino")
      expect(note.reload.slug).to eq("destino-1")
    end

    it "removes stale redirect when new slug matches an existing redirect" do
      # note starts with slug "titulo-original"
      # rename to "Outro" → creates redirect "titulo-original"
      described_class.call(note: note, new_title: "Outro")
      expect(SlugRedirect.find_by(slug: "titulo-original")).to be_present

      # rename back to "Titulo Original" → redirect "titulo-original" should be removed
      described_class.call(note: note, new_title: "Titulo Original")
      expect(note.reload.slug).to eq("titulo-original")
      expect(SlugRedirect.find_by(slug: "titulo-original")).to be_nil
    end

    it "displaces redirect from another note when slug collision occurs in redirects" do
      other_note = create(:note, title: "Alvo")
      # rename other_note → creates redirect "alvo"
      described_class.call(note: other_note, new_title: "Alvo Renomeado")
      expect(SlugRedirect.find_by(slug: "alvo")).to be_present

      # now rename note to "Alvo" → "alvo" becomes note's slug, redirect for other_note displaced
      described_class.call(note: note, new_title: "Alvo")
      expect(note.reload.slug).to eq("alvo")
      expect(SlugRedirect.find_by(slug: "alvo")).to be_nil
    end

    it "preserves UUID-based wikilinks" do
      target = create(:note, title: "Target")
      revision = create(:note_revision, note: note, revision_kind: :checkpoint,
        content_markdown: "Link para [[Target|#{target.id}]]")
      note.update_columns(head_revision_id: revision.id)
      NoteLink.create!(src_note_id: note.id, dst_note_id: target.id, created_in_revision: revision)

      described_class.call(note: target, new_title: "Target Renomeado")

      link = NoteLink.find_by(src_note_id: note.id, dst_note_id: target.id)
      expect(link).to be_present
    end

    it "no-ops when title is unchanged" do
      expect {
        result = described_class.call(note: note, new_title: note.title)
        expect(result.slug_changed).to be false
      }.not_to change(SlugRedirect, :count)
    end

    it "no-ops when new title produces the same slug" do
      expect {
        result = described_class.call(note: note, new_title: "Titulo Original!")
        expect(result.slug_changed).to be false
      }.not_to change(SlugRedirect, :count)
    end

    it "raises ArgumentError for blank title" do
      expect { described_class.call(note: note, new_title: "") }
        .to raise_error(ArgumentError, "Title cannot be blank")
    end

    it "returns a result with old and new slugs" do
      old_slug = note.slug
      result = described_class.call(note: note, new_title: "Resultado")
      expect(result.old_slug).to eq(old_slug)
      expect(result.new_slug).to eq("resultado")
      expect(result.note).to eq(note)
    end
  end
end
