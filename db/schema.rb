# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_04_20_230000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pg_trgm"
  enable_extension "pgcrypto"
  enable_extension "unaccent"

  # Custom types defined in this database.
  # Note that some types may not work with other database engines. Be careful if changing database.
  create_enum "note_revision_kind", ["draft", "checkpoint"]

  create_table "active_storage_attachments", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.uuid "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "agent_messages", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.text "content", null: false
    t.datetime "created_at", null: false
    t.datetime "delivered_at"
    t.uuid "from_note_id", null: false
    t.uuid "to_note_id", null: false
    t.datetime "updated_at", null: false
    t.index ["from_note_id", "created_at"], name: "idx_agent_messages_outbox"
    t.index ["to_note_id", "delivered_at", "created_at"], name: "idx_agent_messages_inbox"
  end

  create_table "ai_providers", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "base_url"
    t.jsonb "config", default: {}
    t.datetime "created_at", null: false
    t.string "default_model_text"
    t.boolean "enabled", default: false, null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_ai_providers_on_name", unique: true
  end

  create_table "ai_requests", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.integer "attempts_count", default: 0, null: false
    t.string "capability", null: false
    t.datetime "completed_at"
    t.decimal "cost_estimate", precision: 10, scale: 6
    t.datetime "created_at", null: false
    t.text "error_message"
    t.text "input_text"
    t.datetime "last_error_at"
    t.string "last_error_kind"
    t.integer "max_attempts", default: 3, null: false
    t.jsonb "metadata", default: {}, null: false
    t.string "model"
    t.datetime "next_retry_at"
    t.uuid "note_revision_id", null: false
    t.text "output_text"
    t.text "prompt_summary"
    t.string "provider", null: false
    t.integer "queue_position", null: false
    t.string "request_hash"
    t.string "requested_provider"
    t.text "response_summary"
    t.datetime "started_at"
    t.string "status", default: "queued", null: false
    t.integer "tokens_in"
    t.integer "tokens_out"
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_ai_requests_on_created_at"
    t.index ["last_error_kind"], name: "index_ai_requests_on_last_error_kind"
    t.index ["next_retry_at"], name: "index_ai_requests_on_next_retry_at"
    t.index ["note_revision_id"], name: "index_ai_requests_on_note_revision_id"
    t.index ["requested_provider"], name: "index_ai_requests_on_requested_provider"
    t.index ["status", "queue_position", "created_at"], name: "index_ai_requests_on_status_and_queue_position_and_created_at"
    t.index ["status"], name: "index_ai_requests_on_status"
  end

  create_table "file_imports", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "base_tag", null: false
    t.datetime "completed_at"
    t.jsonb "confirmed_splits"
    t.text "converted_markdown"
    t.datetime "created_at", null: false
    t.jsonb "created_notes_data", default: []
    t.text "error_message"
    t.string "extra_tags"
    t.string "import_tag", null: false
    t.integer "notes_created", default: 0
    t.string "original_filename", null: false
    t.integer "split_level"
    t.datetime "started_at"
    t.string "status", default: "pending", null: false
    t.jsonb "suggested_splits", default: []
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.index ["user_id"], name: "index_file_imports_on_user_id"
  end

  create_table "link_tags", id: false, force: :cascade do |t|
    t.datetime "created_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.uuid "note_link_id", null: false
    t.uuid "tag_id", null: false
    t.index ["note_link_id", "tag_id"], name: "index_link_tags_on_note_link_id_and_tag_id", unique: true
    t.index ["note_link_id"], name: "index_link_tags_on_note_link_id"
    t.index ["tag_id"], name: "index_link_tags_on_tag_id"
  end

  create_table "mention_exclusions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "matched_term", null: false
    t.uuid "note_id", null: false
    t.uuid "source_note_id", null: false
    t.datetime "updated_at", null: false
    t.index ["note_id", "source_note_id", "matched_term"], name: "idx_mention_exclusions_unique", unique: true
    t.index ["note_id"], name: "index_mention_exclusions_on_note_id"
    t.index ["source_note_id"], name: "index_mention_exclusions_on_source_note_id"
  end

  create_table "note_aliases", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.uuid "note_id", null: false
    t.datetime "updated_at", null: false
    t.index "lower((name)::text)", name: "index_note_aliases_on_lower_name", unique: true
    t.index ["name"], name: "index_note_aliases_on_name_trgm", opclass: :gin_trgm_ops, using: :gin
    t.index ["note_id"], name: "index_note_aliases_on_note_id"
  end

  create_table "note_blocks", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "block_id", null: false
    t.string "block_type", null: false
    t.text "content", null: false
    t.datetime "created_at", null: false
    t.uuid "note_id", null: false
    t.integer "position", null: false
    t.datetime "updated_at", null: false
    t.index ["content"], name: "idx_note_blocks_content_trgm", opclass: :gin_trgm_ops, using: :gin
    t.index ["note_id", "block_id"], name: "idx_note_blocks_note_block_id", unique: true
    t.index ["note_id", "position"], name: "idx_note_blocks_note_position"
    t.index ["note_id"], name: "index_note_blocks_on_note_id"
  end

  create_table "note_headings", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "level", null: false
    t.uuid "note_id", null: false
    t.integer "position", null: false
    t.string "slug", null: false
    t.string "text", null: false
    t.datetime "updated_at", null: false
    t.index ["note_id", "position"], name: "idx_note_headings_note_position"
    t.index ["note_id", "slug"], name: "idx_note_headings_note_slug", unique: true
    t.index ["note_id"], name: "index_note_headings_on_note_id"
    t.index ["text"], name: "idx_note_headings_text_trgm", opclass: :gin_trgm_ops, using: :gin
  end

  create_table "note_links", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.jsonb "context", default: {}
    t.datetime "created_at", null: false
    t.uuid "created_in_revision_id", null: false
    t.uuid "dst_note_id", null: false
    t.string "hier_role"
    t.uuid "src_note_id", null: false
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_note_links_on_active"
    t.index ["created_in_revision_id"], name: "index_note_links_on_created_in_revision_id"
    t.index ["dst_note_id"], name: "index_note_links_on_dst_note_id"
    t.index ["hier_role"], name: "index_note_links_on_hier_role"
    t.index ["src_note_id", "dst_note_id", "hier_role"], name: "index_note_links_unique_src_dst_role", unique: true, where: "(hier_role IS NOT NULL)"
    t.index ["src_note_id", "dst_note_id"], name: "index_note_links_on_src_note_id_and_dst_note_id", unique: true
    t.index ["src_note_id", "dst_note_id"], name: "index_note_links_unique_src_dst_no_role", unique: true, where: "(hier_role IS NULL)"
    t.index ["src_note_id"], name: "index_note_links_on_src_note_id"
  end

  create_table "note_revisions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.boolean "ai_generated", default: false, null: false
    t.uuid "author_id"
    t.uuid "base_revision_id"
    t.string "change_summary"
    t.text "content_markdown", null: false
    t.text "content_plain"
    t.datetime "created_at", null: false
    t.uuid "note_id", null: false
    t.jsonb "properties_data", default: {}, null: false
    t.enum "revision_kind", default: "checkpoint", null: false, enum_type: "note_revision_kind"
    t.datetime "updated_at", null: false
    t.index "to_tsvector('simple'::regconfig, COALESCE(content_plain, ''::text))", name: "index_note_revisions_on_content_plain_tsvector", using: :gin
    t.index ["author_id"], name: "index_note_revisions_on_author_id"
    t.index ["content_plain"], name: "index_note_revisions_on_content_plain", opclass: :gin_trgm_ops, using: :gin
    t.index ["created_at"], name: "index_note_revisions_on_created_at"
    t.index ["note_id", "revision_kind"], name: "index_note_revisions_draft_per_note", where: "(revision_kind = 'draft'::note_revision_kind)"
    t.index ["note_id"], name: "index_note_revisions_on_note_id"
    t.index ["properties_data"], name: "index_note_revisions_on_properties_data", using: :gin
  end

  create_table "note_tags", id: false, force: :cascade do |t|
    t.datetime "created_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.uuid "note_id", null: false
    t.uuid "tag_id", null: false
    t.index ["note_id", "tag_id"], name: "index_note_tags_on_note_id_and_tag_id", unique: true
    t.index ["note_id"], name: "index_note_tags_on_note_id"
    t.index ["tag_id"], name: "index_note_tags_on_tag_id"
  end

  create_table "note_tts_assets", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.jsonb "alignment_data"
    t.string "alignment_status"
    t.datetime "created_at", null: false
    t.integer "duration_ms"
    t.string "format", default: "mp3", null: false
    t.boolean "is_active", default: true, null: false
    t.string "language", null: false
    t.string "model"
    t.uuid "note_revision_id", null: false
    t.string "provider", null: false
    t.string "settings_hash", null: false
    t.string "text_sha256", null: false
    t.datetime "updated_at", null: false
    t.string "voice", null: false
    t.index ["note_revision_id"], name: "index_note_tts_assets_on_note_revision_id"
    t.index ["text_sha256", "language", "voice", "provider", "model", "settings_hash", "is_active"], name: "index_note_tts_assets_on_cache_key"
  end

  create_table "note_views", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.jsonb "columns", default: [], null: false
    t.datetime "created_at", null: false
    t.string "display_type", default: "table", null: false
    t.string "filter_query", default: "", null: false
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.jsonb "sort_config", default: {}, null: false
    t.datetime "updated_at", null: false
    t.index ["position"], name: "index_note_views_on_position"
  end

  create_table "notes", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.string "detected_language"
    t.uuid "head_revision_id"
    t.string "note_kind", default: "markdown", null: false
    t.string "slug", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["deleted_at"], name: "index_notes_on_deleted_at"
    t.index ["head_revision_id"], name: "index_notes_on_head_revision_id"
    t.index ["slug"], name: "index_notes_on_slug", unique: true
    t.index ["title"], name: "index_notes_on_title", opclass: :gin_trgm_ops, using: :gin
  end

  create_table "property_definitions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.boolean "archived", default: false, null: false
    t.jsonb "config", default: {}, null: false
    t.datetime "created_at", null: false
    t.string "description"
    t.string "key", null: false
    t.string "label"
    t.integer "position", default: 0, null: false
    t.boolean "system", default: false, null: false
    t.datetime "updated_at", null: false
    t.string "value_type", null: false
    t.index ["key"], name: "index_property_definitions_on_key", unique: true
  end

  create_table "slug_redirects", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.uuid "note_id", null: false
    t.string "slug", null: false
    t.datetime "updated_at", null: false
    t.index ["note_id"], name: "index_slug_redirects_on_note_id"
    t.index ["slug"], name: "index_slug_redirects_on_slug", unique: true
  end

  create_table "tags", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "color_hex"
    t.datetime "created_at", null: false
    t.string "icon"
    t.string "name", null: false
    t.string "tag_scope", default: "both", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_tags_on_name", unique: true
  end

  create_table "users", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "current_sign_in_at"
    t.string "current_sign_in_ip"
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.datetime "last_sign_in_at"
    t.string "last_sign_in_ip"
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.integer "sign_in_count", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "agent_messages", "notes", column: "from_note_id", on_delete: :cascade
  add_foreign_key "agent_messages", "notes", column: "to_note_id", on_delete: :cascade
  add_foreign_key "ai_requests", "note_revisions"
  add_foreign_key "file_imports", "users"
  add_foreign_key "link_tags", "note_links"
  add_foreign_key "link_tags", "tags"
  add_foreign_key "mention_exclusions", "notes", column: "source_note_id", on_delete: :cascade
  add_foreign_key "mention_exclusions", "notes", on_delete: :cascade
  add_foreign_key "note_aliases", "notes"
  add_foreign_key "note_blocks", "notes", on_delete: :cascade
  add_foreign_key "note_headings", "notes", on_delete: :cascade
  add_foreign_key "note_links", "note_revisions", column: "created_in_revision_id"
  add_foreign_key "note_links", "notes", column: "dst_note_id"
  add_foreign_key "note_links", "notes", column: "src_note_id"
  add_foreign_key "note_revisions", "note_revisions", column: "base_revision_id", on_delete: :nullify
  add_foreign_key "note_revisions", "notes"
  add_foreign_key "note_revisions", "users", column: "author_id"
  add_foreign_key "note_tags", "notes"
  add_foreign_key "note_tags", "tags"
  add_foreign_key "note_tts_assets", "note_revisions"
  add_foreign_key "notes", "note_revisions", column: "head_revision_id", on_delete: :nullify
  add_foreign_key "slug_redirects", "notes"
end
