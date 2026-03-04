FactoryBot.define do
  factory :note_link do
    src_note { create(:note) }
    dst_note { create(:note) }
    created_in_revision { create(:note_revision, note: src_note) }
    hier_role { nil }
    context { {} }
  end
end
