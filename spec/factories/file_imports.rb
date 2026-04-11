# frozen_string_literal: true

FactoryBot.define do
  factory :file_import do
    user
    base_tag { "test-book" }
    import_tag { "test-book-import-#{SecureRandom.hex(4)}" }
    original_filename { "test_import.txt" }
    status { "pending" }

    after(:build) do |fi|
      unless fi.source_file.attached?
        fi.source_file.attach(
          io: File.open(Rails.root.join("spec/fixtures/files/test_import.txt")),
          filename: fi.original_filename,
          content_type: "text/plain"
        )
      end
    end

    trait :failed do
      status { "failed" }
      error_message { "[converting] markitdown crashed" }
    end

    trait :preview do
      status { "preview" }
      started_at { 1.minute.ago }
      converted_markdown { "# Test\n\n## Section 1\n\nContent." }
      suggested_splits { [{ "title" => "Test", "start_line" => 0, "end_line" => 4, "line_count" => 5, "level" => 1 }] }
    end

    trait :completed do
      status { "completed" }
      notes_created { 4 }
      started_at { 1.minute.ago }
      completed_at { Time.current }
      created_notes_data { [{ "slug" => "test-note", "title" => "Test Note" }] }
    end
  end
end
