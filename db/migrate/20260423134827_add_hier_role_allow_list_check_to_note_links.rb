class AddHierRoleAllowListCheckToNoteLinks < ActiveRecord::Migration[8.1]
  CONSTRAINT_NAME = "check_note_links_hier_role_allow_list"

  # Frozen at ship time (2026-04-23). Mirror of NoteLink::Roles::SEMANTIC_NAMES
  # when this migration shipped. If the vocabulary evolves, add a new migration
  # that drops this constraint and recreates it with the updated list — do NOT
  # edit this array in place. Keeping the values inline guarantees that schema
  # replay produces the same constraint as the one shipped to production,
  # regardless of later changes to app constants or autoload paths.
  ALLOWED_ROLES = %w[
    target_is_parent
    target_is_child
    same_level
    next_in_sequence
    delegation_pending
    delegation_directive
    delegation_verify
    delegation_block
  ].freeze

  def up
    remove_check_constraint :note_links, name: CONSTRAINT_NAME, if_exists: true

    allow_list = ALLOWED_ROLES.map { |name| connection.quote(name) }.join(", ")
    add_check_constraint :note_links,
      "hier_role IS NULL OR hier_role IN (#{allow_list})",
      name: CONSTRAINT_NAME,
      validate: true
  end

  def down
    remove_check_constraint :note_links, name: CONSTRAINT_NAME, if_exists: true
  end
end
