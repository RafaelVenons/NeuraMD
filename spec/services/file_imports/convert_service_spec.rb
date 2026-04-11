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

    it "converts a PDF using pymupdf4llm" do
      Tempfile.create(["test", ".pdf"]) do |f|
        f.write("%PDF-1.0\n1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj\n2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj\n3 0 obj<</Type/Page/MediaBox[0 0 612 792]/Parent 2 0 R/Resources<</Font<</F1 4 0 R>>>>/Contents 5 0 R>>endobj\n4 0 obj<</Type/Font/Subtype/Type1/BaseFont/Helvetica>>endobj\n5 0 obj<</Length 44>>stream\nBT /F1 12 Tf 100 700 Td (Hello PDF) Tj ET\nendstream\nendobj\nxref\n0 6\n0000000000 65535 f \n0000000009 00000 n \n0000000058 00000 n \n0000000115 00000 n \n0000000266 00000 n \n0000000340 00000 n \ntrailer<</Size 6/Root 1 0 R>>\nstartxref\n434\n%%EOF")
        f.flush
        result = described_class.call(file_path: f.path, content_type: "application/pdf")
        expect(result).to include("Hello PDF")
      end
    end

    it "uses markitdown for non-PDF files" do
      Tempfile.create(["test", ".txt"]) do |f|
        f.write("Plain text content")
        f.flush
        result = described_class.call(file_path: f.path, content_type: "text/plain")
        expect(result).to include("Plain text content")
      end
    end

    it "raises ConversionError on failure" do
      expect {
        described_class.call(file_path: "/nonexistent/file.txt")
      }.to raise_error(FileImports::ConvertService::ConversionError)
    end
  end

  describe ".available?" do
    it "returns true when a converter is installed" do
      expect(described_class.available?).to be true
    end
  end
end
