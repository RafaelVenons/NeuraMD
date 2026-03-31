class SlugRedirect < ApplicationRecord
  belongs_to :note

  validates :slug, presence: true, uniqueness: {case_sensitive: false}
end
