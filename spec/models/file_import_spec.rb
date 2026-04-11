require "rails_helper"

RSpec.describe FileImport do
  let(:user) { User.first || User.create!(email: "test@example.com", password: "password123") }

  describe "validations" do
    it "requires base_tag" do
      import = FileImport.new(user: user, import_tag: "x-import", original_filename: "test.pdf", status: "pending")
      expect(import).not_to be_valid
      expect(import.errors[:base_tag]).to be_present
    end

    it "requires import_tag" do
      import = FileImport.new(user: user, base_tag: "x", original_filename: "test.pdf", status: "pending")
      expect(import).not_to be_valid
      expect(import.errors[:import_tag]).to be_present
    end

    it "requires original_filename" do
      import = FileImport.new(user: user, base_tag: "x", import_tag: "x-import", status: "pending")
      expect(import).not_to be_valid
      expect(import.errors[:original_filename]).to be_present
    end

    it "validates status inclusion" do
      import = FileImport.new(user: user, base_tag: "x", import_tag: "x-import", original_filename: "f.pdf", status: "bogus")
      expect(import).not_to be_valid
      expect(import.errors[:status]).to be_present
    end
  end

  describe "status helpers" do
    it "#completed?" do
      import = FileImport.new(status: "completed")
      expect(import).to be_completed
    end

    it "#failed?" do
      import = FileImport.new(status: "failed")
      expect(import).to be_failed
    end

    it "#preview?" do
      expect(FileImport.new(status: "preview")).to be_preview
      expect(FileImport.new(status: "completed")).not_to be_preview
    end

    it "#processing?" do
      expect(FileImport.new(status: "pending")).to be_processing
      expect(FileImport.new(status: "converting")).to be_processing
      expect(FileImport.new(status: "analyzing")).to be_processing
      expect(FileImport.new(status: "importing")).to be_processing
      expect(FileImport.new(status: "completed")).not_to be_processing
      expect(FileImport.new(status: "preview")).not_to be_processing
    end

    it "accepts analyzing status" do
      import = FileImport.new(status: "analyzing")
      expect(FileImport::STATUSES).to include("analyzing")
      expect(import.status).to eq("analyzing")
    end
  end
end
