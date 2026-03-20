module Notes
  class TranslationNoteService
    LANGUAGE_LABELS = {
      "pt-BR" => "Português",
      "en-US" => "English",
      "es" => "Español",
      "de" => "Deutsch",
      "fr" => "Français",
      "it" => "Italiano",
      "zh-CN" => "简体中文",
      "zh-TW" => "繁體中文",
      "ja-JP" => "日本語",
      "ko-KR" => "한국어"
    }.freeze

    def self.call(source_note:, ai_request:, content:, target_language:, author:, title: nil)
      new(source_note:, ai_request:, content:, target_language:, author:, title:).call
    end

    def initialize(source_note:, ai_request:, content:, target_language:, author:, title:)
      @source_note = source_note
      @ai_request = ai_request
      @content = content.to_s
      @target_language = target_language.to_s
      @author = author
      @title = title.to_s
    end

    def call
      raise ArgumentError, "Conteúdo traduzido vazio." if @content.blank?
      raise ArgumentError, "Idioma alvo inválido." if @target_language.blank?

      existing_note = translated_note_from_request
      return existing_note if existing_note.present?

      ActiveRecord::Base.transaction do
        translated_note = Note.create!(
          title: resolved_title,
          note_kind: @source_note.note_kind,
          detected_language: @target_language
        )

        revision = Notes::CheckpointService.call(
          note: translated_note,
          content: @content,
          author: @author
        )

        NoteLink.find_or_create_by!(
          src_note: @source_note,
          dst_note: translated_note,
          created_in_revision: @ai_request.note_revision,
          hier_role: "same_level"
        )

        NoteLink.find_or_create_by!(
          src_note: translated_note,
          dst_note: @source_note,
          created_in_revision: revision,
          hier_role: "same_level"
        )

        metadata = @ai_request.metadata.merge(
          "translated_note_id" => translated_note.id,
          "translated_note_revision_id" => revision.id,
          "translation_applied_at" => Time.current.iso8601,
          "translation_applied_by_id" => @author&.id
        )
        @ai_request.update!(metadata:)

        translated_note
      end
    end

    private

    def translated_note_from_request
      note_id = @ai_request.metadata["translated_note_id"]
      return if note_id.blank?

      Note.active.find_by(id: note_id)
    end

    def resolved_title
      return @title if @title.present?

      "#{@source_note.title} (#{language_label(@target_language)})"
    end

    def language_label(language)
      LANGUAGE_LABELS[language] || language
    end
  end
end
