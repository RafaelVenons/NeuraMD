module Notes
  class PromiseCreationService
    include ::DomainEvents
    AI_CAPABILITY = "seed_note".freeze
    Result = Struct.new(:note, :created, :seeded, :request, keyword_init: true)

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

      existing_note = find_existing_note
      return Result.new(note: existing_note, created: false, seeded: existing_note.head_revision.present?, request: nil) if existing_note.present?

      note = Note.create!(
        title: @title,
        note_kind: "markdown",
        detected_language: @source_note.detected_language
      )
      publish_event("note.created", note_id: note.id, slug: note.slug, title: note.title)

      return Result.new(note:, created: true, seeded: false, request: nil) if @mode == "blank"

      request = enqueue_seed_request(note)
      Result.new(note: note.reload, created: true, seeded: false, request:)
    end

    private

    def find_existing_note
      Note.active.find_by("LOWER(title) = ?", @title.downcase)
    end

    def enqueue_seed_request(note)
      raise Ai::ProviderUnavailableError, "IA nao configurada." unless Ai::ProviderRegistry.enabled?

      request = Ai::ReviewService.enqueue(
        note: @source_note,
        note_revision: source_revision_for_request,
        capability: AI_CAPABILITY,
        text: prompt_input,
        language: @source_note.detected_language,
        requested_by: @author
      )

      request.update!(
        metadata: request.metadata.merge(
          "promise_note_id" => note.id,
          "promise_note_title" => note.title,
          "promise_source_note_id" => @source_note.id,
          "promise_source_note_slug" => @source_note.slug
        )
      )

      request
    end

    def prompt_input
      lines = [
        "Write a markdown note about: #{@title}",
        "",
        "The note must be ENTIRELY about \"#{@title}\" — this is the only topic.",
        "Language: #{@source_note.detected_language || 'auto-detect from title'}.",
        "Return only the markdown body."
      ]

      # Only include source context if it's non-trivial and might help with style/language
      content = source_content.presence
      if content && content.length > 20
        lines += [
          "",
          "--- Style reference (do NOT write about this content, use only for language/tone) ---",
          "Source note title: #{@source_note.title}",
          "Source excerpt: #{content.truncate(300)}"
        ]
      end

      lines.join("\n")
    end

    def source_revision_for_request
      # Queue items must survive editor autosave, which replaces draft revisions.
      @source_note.head_revision ||
        @source_note.note_revisions.find_by(revision_kind: :draft) ||
        @source_note.note_revisions.create!(
          content_markdown: @source_note.title,
          revision_kind: :draft,
          author: @author
        )
    end

    def source_content
      @source_note.note_revisions.find_by(revision_kind: :draft)&.content_markdown ||
        @source_note.head_revision&.content_markdown.to_s
    end
  end
end
