class User < ApplicationRecord
  devise :database_authenticatable, :registerable,
    :recoverable, :rememberable, :trackable, :validatable

  has_many :note_revisions, foreign_key: :author_id, dependent: :nullify
end
