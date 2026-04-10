require "rails_helper"

RSpec.describe FileImports::ProcessJob do
  let(:user) { User.first || User.create!(email: "test@example.com", password: "password123") }
  let(:import) do
    fi = FileImport.new(
      user: user,
      base_tag: "test-book",
      import_tag: "test-book-import",
      split_level: -1,
      original_filename: "test.txt",
      status: "pending"
    )
    fi.source_file.attach(
      io: StringIO.new("# My Book\n\nIntro.\n\n## Chapter 1\n\nContent.\n\n## Chapter 2\n\nMore content."),
      filename: "test.txt",
      content_type: "text/plain"
    )
    fi.save!
    fi
  end

  it "processes a text file end-to-end" do
    described_class.perform_now(import.id)
    import.reload

    expect(import.status).to eq("completed")
    expect(import.notes_created).to be >= 1
    expect(import.converted_markdown).to be_present
    expect(import.completed_at).to be_present
  end

  it "transitions through converting → importing → completed" do
    statuses = []
    allow_any_instance_of(FileImport).to receive(:broadcast_progress!) { |fi|
      statuses << fi.status
    }

    described_class.perform_now(import.id)

    expect(statuses).to include("converting", "importing", "completed")
  end

  it "sets failed status on conversion error" do
    fi = FileImport.new(
      user: user,
      base_tag: "x",
      import_tag: "x-import",
      original_filename: "bad.pdf",
      status: "pending"
    )
    fi.source_file.attach(io: StringIO.new("test"), filename: "bad.pdf", content_type: "application/pdf")
    fi.save!

    allow(FileImports::ConvertService).to receive(:call)
      .and_raise(FileImports::ConvertService::ConversionError, "markitdown crashed")

    described_class.perform_now(fi.id)
    fi.reload

    expect(fi.status).to eq("failed")
    expect(fi.error_message).to include("[converting]")
    expect(fi.error_message).to include("markitdown crashed")
  end
end
