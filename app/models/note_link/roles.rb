class NoteLink
  module Roles
    TOKEN_TO_SEMANTIC = {
      "f" => "target_is_parent",
      "c" => "target_is_child",
      "b" => "same_level",
      "n" => "next_in_sequence",
      "p" => "delegation_pending",
      "d" => "delegation_directive",
      "v" => "delegation_verify",
      "x" => "delegation_block"
    }.freeze

    SEMANTIC_NAMES = TOKEN_TO_SEMANTIC.values.freeze
    SEMANTIC_TO_TOKEN = TOKEN_TO_SEMANTIC.invert.freeze
  end
end
