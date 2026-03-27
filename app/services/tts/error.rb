module Tts
  class Error < StandardError; end
  class ProviderUnavailableError < Error; end
  class RequestError < Error; end
  class TransientRequestError < RequestError; end
  class PermanentRequestError < RequestError; end
end
