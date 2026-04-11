# frozen_string_literal: true

require "open3"

module FileImports
  class ConvertService
    ConversionError = Class.new(StandardError)

    PDF_CONTENT_TYPES = %w[application/pdf].freeze

    def self.call(file_path:, content_type: nil)
      if pdf?(file_path, content_type)
        convert_pdf(file_path)
      else
        convert_with_markitdown(file_path)
      end
    end

    def self.available?
      pdf_converter_available? || markitdown_available?
    end

    def self.pdf_converter_available?
      _, _, status = Open3.capture3("uv", "run", "--with", "pymupdf4llm", "python3", "-c", "import pymupdf4llm")
      status.success?
    rescue Errno::ENOENT
      false
    end

    def self.markitdown_available?
      system("which markitdown > /dev/null 2>&1")
    end

    private_class_method def self.pdf?(file_path, content_type)
      return true if PDF_CONTENT_TYPES.include?(content_type)
      file_path.to_s.downcase.end_with?(".pdf")
    end

    private_class_method def self.convert_pdf(file_path)
      pdf2md = Rails.root.join("bin/pdf2md").to_s
      stdout, stderr, status = Open3.capture3("uv", "run", "--with", "pymupdf4llm", pdf2md, file_path.to_s)
      raise ConversionError, "pymupdf4llm exit #{status.exitstatus}: #{stderr.truncate(500)}" unless status.success?
      raise ConversionError, "pymupdf4llm produced empty output" if stdout.strip.blank?
      stdout
    end

    private_class_method def self.convert_with_markitdown(file_path)
      stdout, stderr, status = Open3.capture3("markitdown", file_path.to_s)
      raise ConversionError, "markitdown exit #{status.exitstatus}: #{stderr.truncate(500)}" unless status.success?
      raise ConversionError, "markitdown produced empty output" if stdout.strip.blank?
      stdout
    end
  end
end
