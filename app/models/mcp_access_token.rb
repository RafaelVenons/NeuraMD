# frozen_string_literal: true

class McpAccessToken < ApplicationRecord
  KNOWN_SCOPES = %w[read write tentacle].freeze

  Issued = Struct.new(:record, :plaintext, keyword_init: true)

  validates :name, presence: true
  validates :token_hash, presence: true, uniqueness: true
  validate :scopes_must_be_known

  scope :active, -> { where(revoked_at: nil) }

  class << self
    def issue!(name:, scopes:)
      plaintext = SecureRandom.hex(32)
      record = create!(name: name, scopes: Array(scopes).map(&:to_s), token_hash: hash_for(plaintext))
      Issued.new(record: record, plaintext: plaintext)
    end

    def authenticate(plaintext)
      return nil if plaintext.blank?
      active.find_by(token_hash: hash_for(plaintext))
    end

    def hash_for(plaintext)
      Digest::SHA256.hexdigest(plaintext)
    end
  end

  def scope?(name)
    scopes.include?(name.to_s)
  end

  def revoked?
    revoked_at.present?
  end

  def touch_used!
    update_columns(last_used_at: Time.current)
  end

  private

  def scopes_must_be_known
    unknown = Array(scopes) - KNOWN_SCOPES
    return if unknown.empty?
    errors.add(:scopes, "unknown scope(s): #{unknown.join(", ")}")
  end
end
