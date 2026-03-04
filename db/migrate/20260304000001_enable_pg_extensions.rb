class EnablePgExtensions < ActiveRecord::Migration[8.1]
  def up
    enable_extension "pgcrypto"   # gen_random_uuid()
    enable_extension "pg_trgm"    # trigram search on titles
    enable_extension "unaccent"   # accent-insensitive search
  end

  def down
    disable_extension "unaccent"
    disable_extension "pg_trgm"
    disable_extension "pgcrypto"
  end
end
