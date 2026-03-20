module Ai
  class Error < StandardError; end
  class ProviderUnavailableError < Error; end
  class InvalidCapabilityError < Error; end
  class RequestError < Error; end
end
