class NoteAlias < ApplicationRecord
  belongs_to :note

  validates :name, presence: true,
    uniqueness: {case_sensitive: false},
    length: {maximum: 255}
  validate :name_not_collide_with_slug

  private

  def name_not_collide_with_slug
    return if name.blank?
    if Note.exists?(slug: name.strip.downcase)
      errors.add(:name, "conflicts with an existing note slug")
    end
  end
end
