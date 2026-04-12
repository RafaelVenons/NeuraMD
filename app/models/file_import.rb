# frozen_string_literal: true

class FileImport < ApplicationRecord
  STATUSES = %w[pending converting enriching analyzing preview importing completed failed].freeze
  ACCEPTED_TYPES = %w[
    application/pdf
    application/vnd.openxmlformats-officedocument.wordprocessingml.document
    application/vnd.openxmlformats-officedocument.presentationml.presentation
    application/epub+zip
    text/html
    text/markdown
    text/plain
  ].freeze

  belongs_to :user
  has_one_attached :source_file

  validates :base_tag, presence: true
  validates :import_tag, presence: true
  validates :original_filename, presence: true
  validates :status, inclusion: {in: STATUSES}
  validates :source_file, presence: true, on: :create

  scope :recent, -> { order(created_at: :desc) }

  def broadcast_progress!
    broadcast_replace_later_to(
      self,
      target: "file_import_status",
      partial: "file_imports/status",
      locals: {file_import: self}
    )
  end

  def completed? = status == "completed"
  def failed? = status == "failed"
  def preview? = status == "preview"
  def processing? = status.in?(%w[pending converting enriching analyzing importing])
end
