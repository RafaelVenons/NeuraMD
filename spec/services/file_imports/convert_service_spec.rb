require "rails_helper"

RSpec.describe FileImports::ConvertService do
  describe ".call" do
    it "returns markdown from a text file" do
      Tempfile.create(["test", ".txt"]) do |f|
        f.write("Hello World")
        f.flush
        result = described_class.call(file_path: f.path)
        expect(result).to include("Hello World")
      end
    end

    it "raises ConversionError on failure" do
      expect {
        described_class.call(file_path: "/nonexistent/file.pdf")
      }.to raise_error(FileImports::ConvertService::ConversionError)
    end
  end

  describe ".available?" do
    it "returns true when markitdown is installed" do
      expect(described_class.available?).to be true
    end
  end
end
