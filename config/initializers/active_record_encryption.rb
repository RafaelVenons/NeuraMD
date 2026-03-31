# Development and test must use one stable local keyset, regardless of `.env`,
# so content written by scripts, specs and the web server stays mutually readable.
if Rails.env.development? || Rails.env.test?
  ActiveRecord::Encryption.configure(
    primary_key: "0123456789abcdef0123456789abcdef",
    deterministic_key: "abcdef0123456789abcdef0123456789",
    key_derivation_salt: "1234567890abcdef1234567890abcdef"
  )
else
  primary_key = ENV["ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY"]
  deterministic_key = ENV["ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY"]
  key_derivation_salt = ENV["ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT"]

  ActiveRecord::Encryption.configure(
    primary_key: primary_key,
    deterministic_key: deterministic_key,
    key_derivation_salt: key_derivation_salt
  ) if primary_key.present?
end
