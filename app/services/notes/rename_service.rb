module Notes
  class RenameService
    Result = Struct.new(:note, :old_slug, :new_slug, :slug_changed, keyword_init: true)

    def self.call(note:, new_title:)
      new(note:, new_title:).call
    end

    def initialize(note:, new_title:)
      @note = note
      @new_title = new_title.to_s.strip
    end

    def call
      raise ArgumentError, "Title cannot be blank" if @new_title.blank?

      old_slug = @note.slug
      new_slug = generate_slug(@new_title)

      return no_change_result if @note.title == @new_title && new_slug == old_slug
      return no_change_result if new_slug == old_slug

      ActiveRecord::Base.transaction do
        SlugRedirect.where(slug: new_slug).delete_all
        SlugRedirect.where(slug: old_slug).delete_all
        @note.slug_redirects.create!(slug: old_slug)
        @note.update_columns(title: @new_title, slug: new_slug, updated_at: Time.current)
      end

      Result.new(note: @note, old_slug:, new_slug:, slug_changed: true)
    end

    private

    def no_change_result
      @note.update_columns(title: @new_title, updated_at: Time.current) if @note.title != @new_title
      Result.new(note: @note, old_slug: @note.slug, new_slug: @note.slug, slug_changed: false)
    end

    def generate_slug(title)
      base = title.downcase.gsub(/[^\w\s-]/, "").gsub(/\s+/, "-").gsub(/-+/, "-").strip
      candidate = base.presence || "nota"
      counter = 0
      loop do
        slug = counter.zero? ? candidate : "#{candidate}-#{counter}"
        return slug unless Note.where.not(id: @note.id).exists?(slug: slug)
        counter += 1
      end
    end
  end
end
