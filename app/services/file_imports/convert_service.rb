# frozen_string_literal: true

require "open3"

module FileImports
  class ConvertService
    ConversionError = Class.new(StandardError)

    def self.call(file_path:)
      stdout, stderr, status = Open3.capture3("markitdown", file_path.to_s)
      raise ConversionError, "markitdown exit #{status.exitstatus}: #{stderr.truncate(500)}" unless status.success?
      raise ConversionError, "markitdown produced empty output" if stdout.strip.blank?
      stdout
    end

    def self.available?
      system("which markitdown > /dev/null 2>&1")
    end
  end
end
