# frozen_string_literal: true

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

  it "processes a text file and stops at preview" do
    described_class.perform_now(import.id)
    import.reload

    expect(import.status).to eq("preview")
    expect(import.converted_markdown).to be_present
    expect(import.suggested_splits).to be_an(Array)
    expect(import.suggested_splits).not_to be_empty
    expect(import.suggested_splits.first).to include("title", "start_line", "end_line")
  end

  it "transitions through converting → analyzing → preview when AI is available" do
    statuses = []
    allow_any_instance_of(FileImport).to receive(:broadcast_progress!) { |fi|
      statuses << fi.status
    }
    allow(Ai::ProviderRegistry).to receive(:enabled?).and_return(true)
    allow(Ai::ProviderRegistry).to receive(:available_provider_names).and_return(["ollama"])
    allow(FileImports::AiAnalyzeService).to receive(:call).and_return(nil)

    described_class.perform_now(import.id)

    expect(statuses).to include("converting", "analyzing", "preview")
    expect(statuses).not_to include("importing", "completed")
  end

  it "transitions through converting → preview when AI is disabled" do
    statuses = []
    allow_any_instance_of(FileImport).to receive(:broadcast_progress!) { |fi|
      statuses << fi.status
    }
    allow(Ai::ProviderRegistry).to receive(:enabled?).and_return(false)

    described_class.perform_now(import.id)

    expect(statuses).to include("converting", "preview")
    expect(statuses).not_to include("analyzing")
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

  it "sets failed status when sanitization rejects the markdown" do
    fi = FileImport.new(
      user: user,
      base_tag: "bad-pdf",
      import_tag: "bad-pdf-import",
      original_filename: "corrupt.pdf",
      status: "pending"
    )
    fi.source_file.attach(io: StringIO.new("test"), filename: "corrupt.pdf", content_type: "application/pdf")
    fi.save!

    cid_garbage = (1..150).map { |i| "word(cid:#{i})text" }.join("\n")
    allow(FileImports::ConvertService).to receive(:call).and_return(cid_garbage)

    described_class.perform_now(fi.id)
    fi.reload

    expect(fi.status).to eq("failed")
    expect(fi.error_message).to include("[quality]")
    expect(fi.error_message).to include("encoding")
  end

  it "stores sanitized markdown with form feeds converted" do
    fi = FileImport.new(
      user: user,
      base_tag: "slides",
      import_tag: "slides-import",
      split_level: -1,
      original_filename: "slides.pdf",
      status: "pending"
    )
    fi.source_file.attach(io: StringIO.new("test"), filename: "slides.pdf", content_type: "application/pdf")
    fi.save!

    slide_md = "Titulo Slide 1\n\nConteudo 1.\fTitulo Slide 2\n\nConteudo 2."
    allow(FileImports::ConvertService).to receive(:call).and_return(slide_md)

    described_class.perform_now(fi.id)
    fi.reload

    expect(fi.status).to eq("preview")
    expect(fi.converted_markdown).to include("# slides\n")
    expect(fi.converted_markdown).to include("## Titulo Slide 1")
    expect(fi.converted_markdown).to include("## Titulo Slide 2")
    expect(fi.suggested_splits.size).to be >= 1
  end
end
