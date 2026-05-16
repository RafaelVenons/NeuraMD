class AddCrossProcessOwnershipToTentacleSessions < ActiveRecord::Migration[8.1]
  def up
    # Host that owns the session process. PTY-mode pids are only
    # meaningful on their own host, so reaping orphaned records must be
    # scoped by host.
    add_column :tentacle_sessions, :host, :string

    # PTY-mode sessions have no dtach socket — only dtach-backed records
    # carry one. Drop the NOT NULL so the PTY path can persist a record
    # (its cross-process trace) without a socket.
    change_column_null :tentacle_sessions, :dtach_socket, true

    # Before this patch there was no DB-level per-note uniqueness, so
    # production may already hold more than one alive row for a note.
    # Refuse to deploy in that state rather than (a) let add_index abort
    # with a cryptic error, or (b) silently relabel the losers to
    # `reaped` — relabeling would hide an OS process that may still be
    # running (split-brain). A migration cannot stop runtime processes;
    # surface the problem loudly so an operator drains the duplicates.
    duplicate_notes = select_values(<<~SQL.squish)
      SELECT tentacle_note_id FROM tentacle_sessions
      WHERE status = 'alive'
      GROUP BY tentacle_note_id
      HAVING COUNT(*) > 1
    SQL
    unless duplicate_notes.empty?
      raise <<~MSG
        tentacle_sessions has #{duplicate_notes.size} note(s) with more than one alive session: #{duplicate_notes.join(", ")}.
        Each note must have at most one alive session before this migration can add the per-note unique index.
        Drain the losing sessions first (terminate them via DELETE /api/s2s/tentacles/:slug or the runtime so their
        records leave 'alive'), then re-run db:migrate.
      MSG
    end

    # The cross-process duplicate-spawn guard: at most one alive session
    # per note, enforced atomically by Postgres regardless of which web
    # process is spawning. A losing concurrent spawn hits RecordNotUnique
    # and cleans up its orphan child.
    add_index :tentacle_sessions, :tentacle_note_id,
      unique: true,
      where: "status = 'alive'",
      name: "index_tentacle_sessions_on_note_alive"
  end

  def down
    remove_index :tentacle_sessions, name: "index_tentacle_sessions_on_note_alive"
    remove_column :tentacle_sessions, :host
    # Intentionally NOT restoring `dtach_socket` NOT NULL: PTY-mode rows
    # persisted while this migration was applied carry a NULL socket, and
    # `change_column_null(..., false)` would abort the rollback on them.
    # Leaving the column nullable is a safe superset — the dtach path
    # always provides a socket regardless.
  end
end
