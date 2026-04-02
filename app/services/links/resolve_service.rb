module Links
  # Resolves a wikilink title to an existing note using a precedence chain:
  #   1. Exact match (case-insensitive): title OR alias
  #   2. Normalized match (accent-insensitive via unaccent): title OR alias
  #   3. Ambiguous → multiple candidates returned
  #   4. Not found
  #
  # Within each tier, title matches are preferred over alias matches (match_kind).
  # Ambiguity across title and alias within the same tier is surfaced, never resolved silently.
  class ResolveService
    Result = Struct.new(:status, :notes, :match_kind, keyword_init: true)

    def self.call(title:, exclude_id: nil)
      new(title: title, exclude_id: exclude_id).call
    end

    def initialize(title:, exclude_id: nil)
      @title = title.to_s.strip
      @exclude_id = exclude_id
    end

    def call
      try_exact || try_normalized || not_found
    end

    private

    def base_scope
      scope = Note.active
      scope = scope.where.not(id: @exclude_id) if @exclude_id.present?
      scope
    end

    def try_exact
      by_title = base_scope.where("LOWER(title) = LOWER(?)", @title).to_a
      by_alias = base_scope
        .joins(:note_aliases)
        .where("LOWER(note_aliases.name) = LOWER(?)", @title).to_a

      candidates = (by_title + by_alias).uniq(&:id)
      return if candidates.empty?
      return Result.new(status: :resolved, notes: candidates, match_kind: by_title.any? ? :exact_title : :exact_alias) if candidates.size == 1
      Result.new(status: :ambiguous, notes: candidates, match_kind: nil)
    end

    def try_normalized
      by_title = base_scope.where("unaccent(LOWER(title)) = unaccent(LOWER(?))", @title).to_a
      by_alias = base_scope
        .joins(:note_aliases)
        .where("unaccent(LOWER(note_aliases.name)) = unaccent(LOWER(?))", @title).to_a

      candidates = (by_title + by_alias).uniq(&:id)
      return if candidates.empty?
      return Result.new(status: :resolved, notes: candidates, match_kind: :normalized) if candidates.size == 1
      Result.new(status: :ambiguous, notes: candidates, match_kind: nil)
    end

    def not_found
      Result.new(status: :not_found, notes: [], match_kind: nil)
    end
  end
end
