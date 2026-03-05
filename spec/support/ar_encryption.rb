# Configure AR Encryption with deterministic test keys
# These are test-only keys — never use in production
ActiveSupport.on_load(:active_record) do
  ActiveRecord::Encryption.configure(
    primary_key: "test-primary-key-32chars-padding!",
    deterministic_key: "test-deterministic-key-32chars!!",
    key_derivation_salt: "test-key-derivation-salt-32chars"
  )
end
