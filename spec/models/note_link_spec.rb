require "rails_helper"

RSpec.describe NoteLink, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:src_note).class_name("Note") }
    it { is_expected.to belong_to(:dst_note).class_name("Note") }
    it { is_expected.to belong_to(:created_in_revision).class_name("NoteRevision") }
    it { is_expected.to have_many(:link_tags).dependent(:destroy) }
    it { is_expected.to have_many(:tags).through(:link_tags) }
  end

  describe "HIER_ROLES" do
    it "matches the semantic names declared by NoteLink::Roles" do
      expect(described_class::HIER_ROLES).to match_array(NoteLink::Roles::SEMANTIC_NAMES)
    end

    it "includes every delegation role" do
      expect(described_class::HIER_ROLES).to include(
        "delegation_pending",
        "delegation_directive",
        "delegation_verify",
        "delegation_block"
      )
    end
  end

  describe "validations" do
    it { is_expected.to validate_inclusion_of(:hier_role).in_array(NoteLink::HIER_ROLES).allow_nil }

    it "prevents self-links" do
      note = create(:note)
      revision = create(:note_revision, note: note)
      link = build(:note_link, src_note: note, dst_note: note, created_in_revision: revision)
      expect(link).not_to be_valid
      expect(link.errors[:dst_note_id]).to be_present
    end

    it "prevents duplicate links between same pair" do
      src = create(:note)
      dst = create(:note)
      revision = create(:note_revision, note: src)
      create(:note_link, src_note: src, dst_note: dst, created_in_revision: revision)
      duplicate = build(:note_link, src_note: src, dst_note: dst, created_in_revision: revision)
      expect(duplicate).not_to be_valid
    end
  end

  describe "database CHECK constraint on hier_role" do
    it "rejects rows whose hier_role is outside the allow-list" do
      src = create(:note)
      dst = create(:note)
      revision = create(:note_revision, note: src)

      expect {
        ActiveRecord::Base.connection.execute(
          ActiveRecord::Base.sanitize_sql_array([
            "INSERT INTO note_links (id, src_note_id, dst_note_id, created_in_revision_id, hier_role, active, created_at, updated_at) " \
            "VALUES (gen_random_uuid(), ?, ?, ?, 'not_a_real_role', true, now(), now())",
            src.id, dst.id, revision.id
          ])
        )
      }.to raise_error(ActiveRecord::StatementInvalid, /check_hier_role_allow_list|check constraint/i)
    end

    it "accepts NULL hier_role" do
      src = create(:note)
      dst = create(:note)
      revision = create(:note_revision, note: src)

      expect {
        ActiveRecord::Base.connection.execute(
          ActiveRecord::Base.sanitize_sql_array([
            "INSERT INTO note_links (id, src_note_id, dst_note_id, created_in_revision_id, hier_role, active, created_at, updated_at) " \
            "VALUES (gen_random_uuid(), ?, ?, ?, NULL, true, now(), now())",
            src.id, dst.id, revision.id
          ])
        )
      }.not_to raise_error
    end

    it "accepts every semantic name declared in NoteLink::Roles::SEMANTIC_NAMES" do
      NoteLink::Roles::SEMANTIC_NAMES.each do |semantic|
        src = create(:note)
        dst = create(:note)
        revision = create(:note_revision, note: src)

        expect {
          ActiveRecord::Base.connection.execute(
            ActiveRecord::Base.sanitize_sql_array([
              "INSERT INTO note_links (id, src_note_id, dst_note_id, created_in_revision_id, hier_role, active, created_at, updated_at) " \
              "VALUES (gen_random_uuid(), ?, ?, ?, ?, true, now(), now())",
              src.id, dst.id, revision.id, semantic
            ])
          )
        }.not_to raise_error, "expected hier_role=#{semantic.inspect} to satisfy the CHECK constraint"
      end
    end
  end
end
