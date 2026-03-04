# AR Encryption keys are loaded from ENV, never hardcoded.
# Required ENVs:
#   ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY
#   ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY
#   ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT
#
# Generate with: bin/rails db:encryption:init
ActiveRecord::Encryption.configure(
  primary_key: ENV["ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY"],
  deterministic_key: ENV["ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY"],
  key_derivation_salt: ENV["ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT"]
) if ENV["ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY"].present?
