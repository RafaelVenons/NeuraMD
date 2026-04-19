require "rails_helper"

RSpec.describe Tentacles::TranscriptService do
  let(:note) do
    create(:note, title: "Tentacle Note").tap do |n|
      rev = create(:note_revision, note: n, content_markdown: "Original body\n")
      n.update_columns(head_revision_id: rev.id)
    end
  end

  let(:started_at) { Time.utc(2026, 4, 19, 12, 0, 0) }
  let(:ended_at) { Time.utc(2026, 4, 19, 12, 5, 30) }
  let(:command) { ["bash", "-l"] }

  describe ".persist" do
    it "appends a transcript section to the note content and creates a checkpoint" do
      expect {
        described_class.persist(
          note: note,
          transcript: "hello\nworld\n",
          command: command,
          started_at: started_at,
          ended_at: ended_at
        )
      }.to change { note.reload.note_revisions.where(revision_kind: :checkpoint).count }.by(1)

      body = note.reload.head_revision.content_markdown
      expect(body).to start_with("Original body")
      expect(body).to include("## Transcript — 2026-04-19T12:00:00Z")
      expect(body).to include("Comando: `bash -l`")
      expect(body).to include("Encerrado em 2026-04-19T12:05:30Z")
      expect(body).to match(/```text\nhello\nworld\n```/)
    end

    it "strips ANSI escape sequences from the transcript body" do
      ansi = "\e[31mred\e[0m plain\r\n\e[2K\e[Gbye\n"
      described_class.persist(
        note: note,
        transcript: ansi,
        command: ["claude"],
        started_at: started_at,
        ended_at: ended_at
      )

      body = note.reload.head_revision.content_markdown
      expect(body).to include("red plain")
      expect(body).to include("bye")
      expect(body).not_to include("\e[31m")
      expect(body).not_to include("\e[0m")
    end

    it "is a no-op when the transcript is blank" do
      expect {
        described_class.persist(
          note: note,
          transcript: "",
          command: command,
          started_at: started_at,
          ended_at: ended_at
        )
      }.not_to change { note.reload.note_revisions.count }
    end

    it "truncates transcripts larger than the size cap" do
      huge = "x" * (Tentacles::TranscriptService::MAX_TRANSCRIPT_BYTES + 5_000)
      described_class.persist(
        note: note,
        transcript: huge,
        command: command,
        started_at: started_at,
        ended_at: ended_at
      )

      body = note.reload.head_revision.content_markdown
      expect(body).to include("[truncated")
      expect(body.bytesize).to be < (Tentacles::TranscriptService::MAX_TRANSCRIPT_BYTES + 2_000)
    end
  end
end
