# Production should provide real credentials via ENV.
# Development and test use a stable local fallback so encrypted content
# created by scripts, specs and local servers stays readable without
# requiring manual env setup on every command.
fallback_keys = if Rails.env.development? || Rails.env.test?
  {
    primary_key: "0123456789abcdef0123456789abcdef",
    deterministic_key: "abcdef0123456789abcdef0123456789",
    key_derivation_salt: "1234567890abcdef1234567890abcdef"
  }
end

primary_key = ENV["ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY"] || fallback_keys&.fetch(:primary_key, nil)
deterministic_key = ENV["ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY"] || fallback_keys&.fetch(:deterministic_key, nil)
key_derivation_salt = ENV["ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT"] || fallback_keys&.fetch(:key_derivation_salt, nil)

ActiveRecord::Encryption.configure(
  primary_key: primary_key,
  deterministic_key: deterministic_key,
  key_derivation_salt: key_derivation_salt
) if primary_key.present?
