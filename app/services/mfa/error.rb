module Mfa
  class Error < StandardError; end
  class ExecutionError < Error; end
  class TransientError < Error; end
  class ConfigurationError < Error; end
end
