# frozen_string_literal: true

require "rails_helper"

RSpec.describe FileImports::ImportJob do
  let(:user) { User.first || User.create!(email: "test@example.com", password: "password123") }

  let(:import) do
    fi = FileImport.new(
      user: user,
      base_tag: "test-book",
      import_tag: "test-book-import-#{SecureRandom.hex(4)}",
      split_level: -1,
      original_filename: "test.txt",
      status: "preview",
      started_at: 1.minute.ago,
      converted_markdown: "# My Book\n\nIntro.\n\n## Chapter 1\n\nContent.\n\n## Chapter 2\n\nMore content.",
      suggested_splits: [
        {"title" => "My Book", "start_line" => 0, "end_line" => 2, "line_count" => 3, "level" => 1},
        {"title" => "Chapter 1", "start_line" => 4, "end_line" => 6, "line_count" => 3, "level" => 2},
        {"title" => "Chapter 2", "start_line" => 8, "end_line" => 10, "line_count" => 3, "level" => 2}
      ]
    )
    fi.source_file.attach(
      io: StringIO.new("test"),
      filename: "test.txt",
      content_type: "text/plain"
    )
    fi.save!
    fi
  end

  it "imports notes from preview state to completed" do
    described_class.perform_now(import.id)
    import.reload

    expect(import.status).to eq("completed")
    expect(import.notes_created).to be >= 1
    expect(import.completed_at).to be_present
    expect(import.created_notes_data).to be_an(Array)
    expect(import.created_notes_data.first).to include("slug", "title")
  end

  it "transitions through importing → completed" do
    statuses = []
    allow_any_instance_of(FileImport).to receive(:broadcast_progress!) { |fi|
      statuses << fi.status
    }

    described_class.perform_now(import.id)

    expect(statuses).to include("importing", "completed")
  end

  it "skips if import is already completed" do
    import.update!(status: "completed", completed_at: Time.current)

    expect {
      described_class.perform_now(import.id)
    }.not_to change { import.reload.updated_at }
  end

  it "fails gracefully when markdown is blank" do
    import.update!(converted_markdown: nil)

    described_class.perform_now(import.id)
    import.reload

    expect(import.status).to eq("failed")
    expect(import.error_message).to include("Markdown")
  end
end
