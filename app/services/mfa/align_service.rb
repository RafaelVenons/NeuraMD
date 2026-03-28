require "fileutils"
require "json"
require_relative "error"

module Mfa
  class AlignService
    # Local (NFS) paths — where Rails reads/writes files
    MFA_INPUT_ROOT = ENV.fetch("MFA_LOCAL_ROOT", "/mnt/AIrch/data/mfa") + "/input"
    MFA_OUTPUT_ROOT = ENV.fetch("MFA_LOCAL_ROOT", "/mnt/AIrch/data/mfa") + "/output"
    ALIGNMENT_ROOT = ENV.fetch("ALIGNMENT_ROOT", "/mnt/AIrch/data/alignments")

    # Remote paths — how the same dirs appear on AIrch (via NFS bind)
    MFA_REMOTE_INPUT = ENV.fetch("MFA_REMOTE_ROOT", "/srv/airch-data/mfa") + "/input"
    MFA_REMOTE_OUTPUT = ENV.fetch("MFA_REMOTE_ROOT", "/srv/airch-data/mfa") + "/output"

    DICTIONARY_MAP = {
      "pt-BR" => "portuguese_brazil_mfa",
      "pt" => "portuguese_mfa",
      "en-US" => "english_mfa",
      "en-GB" => "english_mfa",
      "en" => "english_mfa",
      "es-ES" => "spanish_mfa",
      "es" => "spanish_mfa",
      "fr-FR" => "french_mfa",
      "fr" => "french_mfa",
      "it-IT" => "italian_cv",
      "it" => "italian_cv",
      "zh-CN" => "mandarin_mfa",
      "ja-JP" => "japanese_mfa",
      "ko-KR" => "korean_mfa"
    }.freeze

    ACOUSTIC_MODEL_MAP = {
      "pt-BR" => "portuguese_mfa",
      "pt" => "portuguese_mfa",
      "en-US" => "english_mfa",
      "en-GB" => "english_mfa",
      "en" => "english_mfa",
      "es-ES" => "spanish_mfa",
      "es" => "spanish_mfa",
      "fr-FR" => "french_mfa",
      "fr" => "french_mfa",
      "it-IT" => "italian_cv",
      "it" => "italian_cv",
      "zh-CN" => "mandarin_mfa",
      "ja-JP" => "japanese_mfa",
      "ko-KR" => "korean_mfa"
    }.freeze

    def self.call(tts_asset)
      new(tts_asset).perform
    end

    def initialize(tts_asset)
      @asset = tts_asset
    end

    def perform
      validate!
      prepare_input
      run_alignment
      alignment_data = parse_output
      store_alignment(alignment_data)
      cleanup
      alignment_data
    end

    private

    def validate!
      raise ConfigurationError, "TTS asset has no audio" unless @asset.audio.attached?
      raise ConfigurationError, "Unsupported language: #{@asset.language}" unless dictionary
    end

    def prepare_input
      FileUtils.mkdir_p(input_dir)

      # Write audio file (convert to WAV for MFA compatibility)
      audio_path = File.join(input_dir, "audio.wav")
      @asset.audio.open do |tempfile|
        if @asset.format == "wav"
          FileUtils.cp(tempfile.path, audio_path)
        else
          convert_to_wav(tempfile.path, audio_path)
        end
      end

      # Write transcript — use the cleaned text that was sent to TTS provider
      transcript_path = File.join(input_dir, "audio.txt")
      text = tts_input_text
      File.write(transcript_path, text)
    end

    def run_alignment
      mfa_bin = ENV.fetch("MFA_BIN", "~/.local/share/mamba/envs/mfa/bin/mfa")
      mfa_cmd = [
        mfa_bin, "align",
        File.join(MFA_REMOTE_INPUT, @asset.id.to_s),
        dictionary,
        acoustic_model,
        File.join(MFA_REMOTE_OUTPUT, @asset.id.to_s),
        "--output_format json",
        "--clean"
      ].join(" ")

      executor.execute(mfa_cmd)
    end

    def parse_output
      json_path = File.join(output_dir, "audio.json")

      unless File.exist?(json_path)
        raise ExecutionError, "MFA output not found at #{json_path}"
      end

      raw = JSON.parse(File.read(json_path))
      normalize_alignment(raw)
    end

    def normalize_alignment(raw)
      words = []
      tiers = raw.dig("tiers") || {}

      word_tier = tiers["words"] || tiers.values.find { |t| t["type"] == "words" }
      return {words: [], duration_s: 0} unless word_tier

      entries = word_tier["entries"] || []
      entries.each do |entry|
        next if entry[2].to_s.strip.empty?
        words << {
          word: entry[2].to_s.strip,
          start: entry[0].to_f.round(3),
          end: entry[1].to_f.round(3)
        }
      end

      # Map MFA words (lowercase, no punctuation) back to original words
      # so karaoke preserves casing and punctuation from the preview text.
      original_words = tts_input_text.split(/\s+/)
      if words.length == original_words.length
        words.each_with_index { |w, i| w[:word] = original_words[i] }
      elsif original_words.any?
        remap_words_to_original(words, original_words)
      end

      duration_s = words.any? ? words.last[:end] : 0
      {words: words, duration_s: duration_s.round(3)}
    end

    # Sequential fuzzy matching when MFA word count differs from original.
    # MFA may skip, merge, or split words. Handles:
    # - Direct match: MFA "arroz" ↔ original "arroz"
    # - Split compound: MFA ["bem","estar"] ↔ original "bem-estar"
    def remap_words_to_original(mfa_words, original_words)
      oi = 0
      mi = 0
      while mi < mfa_words.length && oi < original_words.length
        w = mfa_words[mi]
        mfa_norm = normalize_word(w[:word])
        orig_norm = normalize_word(original_words[oi])

        if orig_norm == mfa_norm
          # Direct match
          w[:word] = original_words[oi]
          oi += 1
          mi += 1
        elsif orig_norm.start_with?(mfa_norm) && mi + 1 < mfa_words.length
          # MFA split a compound word (e.g., "bem-estar" → "bem" + "estar")
          # Check if consecutive MFA words form the original word
          combined = mfa_norm
          lookahead = mi + 1
          while lookahead < mfa_words.length && combined.length < orig_norm.length
            combined += normalize_word(mfa_words[lookahead][:word])
            lookahead += 1
          end
          if combined == orig_norm
            # Merge: assign original word to first MFA entry, mark rest for removal
            w[:word] = original_words[oi]
            # Extend first word's timing to cover all parts
            w[:end] = mfa_words[lookahead - 1][:end]
            # Mark split parts for removal
            (mi + 1...lookahead).each { |j| mfa_words[j][:_remove] = true }
            mi = lookahead
            oi += 1
          else
            # No match — skip this MFA word
            mi += 1
          end
        else
          # Try advancing original to find a match
          found = false
          (oi + 1...[oi + 5, original_words.length].min).each do |try_oi|
            if normalize_word(original_words[try_oi]) == mfa_norm
              w[:word] = original_words[try_oi]
              oi = try_oi + 1
              mi += 1
              found = true
              break
            end
          end
          mi += 1 unless found
        end
      end

      # Remove merged split parts
      mfa_words.reject! { |w| w.delete(:_remove) }
    end

    def normalize_word(word)
      word.unicode_normalize(:nfkd).gsub(/[^\p{L}\p{N}]/, "").downcase
    end

    def store_alignment(data)
      @asset.update!(
        alignment_data: data,
        alignment_status: "succeeded"
      )

      # Also save a copy to the shared filesystem
      json_dest = File.join(ALIGNMENT_ROOT, "json", "#{@asset.id}.json")
      FileUtils.mkdir_p(File.dirname(json_dest))
      File.write(json_dest, data.to_json)
    end

    def cleanup
      FileUtils.rm_rf(input_dir)
      FileUtils.rm_rf(output_dir)
    end

    def input_dir
      File.join(MFA_INPUT_ROOT, @asset.id.to_s)
    end

    def output_dir
      File.join(MFA_OUTPUT_ROOT, @asset.id.to_s)
    end

    def dictionary
      DICTIONARY_MAP[@asset.language]
    end

    def acoustic_model
      ACOUSTIC_MODEL_MAP[@asset.language] || dictionary
    end

    def executor
      @executor ||= RemoteExecutor.new
    end

    def tts_input_text
      @tts_input_text ||= begin
        # The AiRequest stores the cleaned text (preview plaintext) sent to TTS
        ai_request = AiRequest.find_by(
          "metadata->>'tts_asset_id' = ?", @asset.id.to_s
        )
        text = ai_request&.input_text.to_s.strip
        if text.present?
          text
        else
          # Fallback: basic cleanup of revision content
          @asset.note_revision&.content_markdown.to_s
            .gsub(/\[\[([^\]|]+)\|[^\]]*\]\]/, '\1')
            .gsub(/[#*_`~\[\]()>]/, "")
            .strip
        end
      end
    end

    def convert_to_wav(src, dst)
      system("ffmpeg", "-y", "-i", src, "-ar", "16000", "-ac", "1", dst,
        out: File::NULL, err: File::NULL)
      raise ExecutionError, "ffmpeg conversion failed" unless File.exist?(dst)
    end
  end
end
