class AddHierRoleAllowListCheckToNoteLinks < ActiveRecord::Migration[8.1]
  CONSTRAINT_NAME = "check_note_links_hier_role_allow_list"

  def up
    remove_check_constraint :note_links, name: CONSTRAINT_NAME, if_exists: true

    allow_list = NoteLink::Roles::SEMANTIC_NAMES.map { |name| connection.quote(name) }.join(", ")
    add_check_constraint :note_links,
      "hier_role IS NULL OR hier_role IN (#{allow_list})",
      name: CONSTRAINT_NAME,
      validate: true
  end

  def down
    remove_check_constraint :note_links, name: CONSTRAINT_NAME, if_exists: true
  end
end
