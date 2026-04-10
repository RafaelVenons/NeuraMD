require "rails_helper"

RSpec.describe "FileImports", type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  describe "GET /file_imports" do
    it "returns http success" do
      get file_imports_path
      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /file_imports/new" do
    it "returns http success" do
      get new_file_import_path
      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST /file_imports" do
    it "creates a file import and enqueues job" do
      file = Tempfile.new(["test", ".txt"])
      file.write("# Test\n\nContent.")
      file.rewind

      uploaded = Rack::Test::UploadedFile.new(file.path, "text/plain")

      expect {
        post file_imports_path, params: {
          file_import: {
            source_file: uploaded,
            base_tag: "test",
            import_tag: "test-import",
            split_level: -1
          }
        }
      }.to change(FileImport, :count).by(1)
       .and have_enqueued_job(FileImports::ProcessJob)

      expect(response).to have_http_status(:redirect)
    ensure
      file&.close
      file&.unlink
    end
  end

  describe "GET /file_imports/:id" do
    it "returns http success" do
      import = FileImport.new(
        user: user,
        base_tag: "x",
        import_tag: "x-import",
        original_filename: "test.txt",
        status: "pending"
      )
      import.source_file.attach(io: StringIO.new("test content"), filename: "test.txt", content_type: "text/plain")
      import.save!

      get file_import_path(import)
      expect(response).to have_http_status(:ok)
    end
  end

  context "without authentication" do
    before { sign_out user }

    it "redirects to login" do
      get file_imports_path
      expect(response).to redirect_to(new_user_session_path)
    end
  end
end
