class NoteLink < ApplicationRecord
  HIER_ROLES = %w[target_is_parent target_is_child same_level].freeze

  belongs_to :src_note, class_name: "Note"
  belongs_to :dst_note, class_name: "Note"
  belongs_to :created_in_revision, class_name: "NoteRevision"
  has_many :link_tags, dependent: :destroy
  has_many :tags, through: :link_tags

  validates :src_note_id, presence: true
  validates :dst_note_id, presence: true
  validates :src_note_id, uniqueness: {scope: [:dst_note_id, :hier_role], message: "already links to this note with the same role"}
  validates :hier_role, inclusion: {in: HIER_ROLES}, allow_nil: true
  validate :no_self_links

  private

  def no_self_links
    errors.add(:dst_note_id, "cannot link a note to itself") if src_note_id == dst_note_id
  end
end
