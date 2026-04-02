module Aliases
  class SetService
    include ::DomainEvents

    Result = Struct.new(:note, :aliases, keyword_init: true)

    def self.call(note:, aliases:, author: nil)
      new(note:, aliases:, author:).call
    end

    def initialize(note:, aliases:, author:)
      @note = note
      @aliases = aliases.map { |a| a.to_s.strip }.reject(&:blank?).uniq { |a| a.downcase }
      @author = author
    end

    def call
      ActiveRecord::Base.transaction do
        current = @note.note_aliases.index_by { |a| a.name.downcase }
        desired = @aliases.index_by { |a| a.downcase }

        to_remove = current.keys - desired.keys
        to_add = desired.keys - current.keys

        @note.note_aliases.where(id: current.values_at(*to_remove).compact.map(&:id)).destroy_all if to_remove.any?

        to_add.each do |key|
          @note.note_aliases.create!(name: desired[key])
        end
      end

      final_aliases = @note.note_aliases.reload.pluck(:name)

      publish_event("note.aliases_changed",
        note_id: @note.id,
        aliases: final_aliases)

      Result.new(note: @note, aliases: final_aliases)
    end
  end
end
