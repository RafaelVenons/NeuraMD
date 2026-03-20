module Notes
  class PromiseCreationService
    AI_CAPABILITY = "seed_note".freeze

    def self.call(source_note:, title:, author:, mode:)
      new(source_note:, title:, author:, mode:).call
    end

    def initialize(source_note:, title:, author:, mode:)
      @source_note = source_note
      @title = title.to_s.squish
      @author = author
      @mode = mode.to_s
    end

    def call
      raise ArgumentError, "Titulo da nota obrigatorio." if @title.blank?
      raise ArgumentError, "Modo invalido." unless %w[blank ai].include?(@mode)

      note = Note.create!(
        title: @title,
        note_kind: "markdown",
        detected_language: @source_note.detected_language
      )

      return note if @mode == "blank"

      content = generate_seed_content
      Notes::CheckpointService.call(note:, content:, author: @author)
      note.reload
    end

    private

    def generate_seed_content
      raise Ai::ProviderUnavailableError, "IA nao configurada." unless Ai::ProviderRegistry.enabled?

      prompt_input = [
        "Create an initial markdown note for the title below.",
        "Use the source note as contextual grounding when helpful.",
        "Return only the markdown body.",
        "",
        "New note title: #{@title}",
        "Source note title: #{@source_note.title}",
        "Source note language: #{@source_note.detected_language}",
        "",
        "Source note content:",
        source_content.presence || "(empty)"
      ].join("\n")

      provider = Ai::ProviderRegistry.build(
        nil,
        capability: AI_CAPABILITY,
        text: prompt_input,
        language: @source_note.detected_language
      )

      provider.review(
        capability: AI_CAPABILITY,
        text: prompt_input,
        language: @source_note.detected_language
      ).content
    end

    def source_content
      @source_note.note_revisions.find_by(revision_kind: :draft)&.content_markdown ||
        @source_note.head_revision&.content_markdown.to_s
    end
  end
end
