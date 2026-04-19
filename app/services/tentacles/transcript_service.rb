module Tentacles
  class TranscriptService
    MAX_TRANSCRIPT_BYTES = 200_000
    ANSI_ESCAPE = /\e\[[0-9;?]*[ -\/]*[@-~]|\e\].*?(?:\a|\e\\)|\e[@-_]/
    CARRIAGE_RETURN_BEFORE_LF = /\r\n/

    def self.persist(note:, transcript:, command:, started_at:, ended_at:, author: nil)
      return if transcript.nil? || transcript.strip.empty?

      body = format_body(transcript)
      header = format_header(command: command, started_at: started_at, ended_at: ended_at)
      section = "#{header}\n\n```text\n#{body}\n```\n"

      current = note.head_revision&.content_markdown.to_s
      new_content = current.empty? ? section : "#{current.rstrip}\n\n#{section}"

      Notes::CheckpointService.call(note: note, content: new_content, author: author)
    end

    def self.format_header(command:, started_at:, ended_at:)
      cmd = Array(command).join(" ")
      <<~MD.strip
        ## Transcript — #{started_at.utc.iso8601}

        Comando: `#{cmd}` — Encerrado em #{ended_at.utc.iso8601}
      MD
    end

    def self.format_body(transcript)
      cleaned = strip_ansi(transcript).gsub(CARRIAGE_RETURN_BEFORE_LF, "\n").gsub("\r", "\n").rstrip
      truncate(cleaned)
    end

    def self.strip_ansi(str)
      str.gsub(ANSI_ESCAPE, "")
    end

    def self.truncate(str)
      return str if str.bytesize <= MAX_TRANSCRIPT_BYTES
      head = str.byteslice(0, MAX_TRANSCRIPT_BYTES)
      head.force_encoding(Encoding::UTF_8).scrub!
      "#{head}\n[truncated — original #{str.bytesize} bytes]"
    end
  end
end
