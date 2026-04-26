FactoryBot.define do
  factory :mcp_access_token do
    sequence(:name) { |n| "token-#{n}" }
    scopes { %w[read] }
    token_hash { McpAccessToken.hash_for(SecureRandom.hex(24)) }
  end
end
