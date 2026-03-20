require "digest"
require_relative "error"
require_relative "provider_registry"

module Ai
  class ReviewService
    CAPABILITIES = %w[suggest rewrite grammar_review].freeze

    class << self
      def status
        ProviderRegistry.status
      end

      def call(note:, note_revision:, capability:, text:, language:, provider_name: nil)
        capability = capability.to_s
        raise InvalidCapabilityError, "Capability de IA invalida." unless CAPABILITIES.include?(capability)
        raise Error, "Nenhum texto para processar." if text.to_s.blank?

        provider = ProviderRegistry.build(provider_name)
        result = provider.review(capability:, text:, language:)

        audit_request!(
          note_revision:,
          capability:,
          text:,
          result:
        )

        result
      end

      private

      def audit_request!(note_revision:, capability:, text:, result:)
        note_revision.ai_requests.create!(
          provider: result.provider,
          capability: capability,
          request_hash: Digest::SHA256.hexdigest([result.provider, result.model, capability, text].join(":")),
          prompt_summary: prompt_summary(capability, text),
          response_summary: result.content.to_s.truncate(240),
          tokens_in: result.tokens_in,
          tokens_out: result.tokens_out
        )
      end

      def prompt_summary(capability, text)
        "#{capability}: #{text.to_s.truncate(240)}"
      end
    end
  end
end
