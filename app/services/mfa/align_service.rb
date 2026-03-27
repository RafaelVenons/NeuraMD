require "fileutils"
require "json"
require_relative "error"

module Mfa
  class AlignService
    MFA_INPUT_ROOT = ENV.fetch("MFA_ROOT", "/mnt/neuramd-share/mfa") + "/input"
    MFA_OUTPUT_ROOT = ENV.fetch("MFA_ROOT", "/mnt/neuramd-share/mfa") + "/output"
    ALIGNMENT_ROOT = ENV.fetch("ALIGNMENT_ROOT", "/mnt/neuramd-share/alignments")

    DICTIONARY_MAP = {
      "pt-BR" => "portuguese_brazil_mfa",
      "pt" => "portuguese_brazil_mfa",
      "en-US" => "english_mfa",
      "en-GB" => "english_mfa",
      "en" => "english_mfa",
      "es-ES" => "spanish_mfa",
      "es" => "spanish_mfa",
      "fr-FR" => "french_mfa",
      "fr" => "french_mfa",
      "it-IT" => "italian_mfa",
      "it" => "italian_mfa",
      "zh-CN" => "mandarin_mfa",
      "ja-JP" => "japanese_mfa",
      "ko-KR" => "korean_mfa",
      "hi-IN" => "hindi_mfa"
    }.freeze

    ACOUSTIC_MODEL_MAP = {
      "pt-BR" => "portuguese_brazil_mfa",
      "pt" => "portuguese_brazil_mfa",
      "en-US" => "english_mfa",
      "en-GB" => "english_mfa",
      "en" => "english_mfa",
      "es-ES" => "spanish_mfa",
      "es" => "spanish_mfa",
      "fr-FR" => "french_mfa",
      "fr" => "french_mfa",
      "it-IT" => "italian_mfa",
      "it" => "italian_mfa",
      "zh-CN" => "mandarin_mfa",
      "ja-JP" => "japanese_mfa",
      "ko-KR" => "korean_mfa",
      "hi-IN" => "hindi_mfa"
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
      mfa_cmd = [
        "mfa align",
        "/mnt/neuramd-share/mfa/input/#{@asset.id}",
        dictionary,
        acoustic_model,
        "/mnt/neuramd-share/mfa/output/#{@asset.id}",
        "--output_format json",
        "--clean"
      ].join(" ")

      executor.docker_exec(mfa_cmd)
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

      duration_s = words.any? ? words.last[:end] : 0
      {words: words, duration_s: duration_s.round(3)}
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
      # The AiRequest stores the cleaned text that was sent to the TTS provider
      ai_request = AiRequest.find_by(
        "metadata->>'tts_asset_id' = ?", @asset.id.to_s
      )
      text = ai_request&.input_text.to_s.strip
      return text if text.present?

      # Fallback: strip markdown from revision content
      @asset.note_revision&.content_markdown.to_s
        .gsub(/\[\[([^\]|]+)\|[^\]]*\]\]/, '\1')
        .gsub(/[#*_`~\[\]()>]/, "")
        .strip
    end

    def convert_to_wav(src, dst)
      system("ffmpeg", "-y", "-i", src, "-ar", "16000", "-ac", "1", dst,
        out: File::NULL, err: File::NULL)
      raise ExecutionError, "ffmpeg conversion failed" unless File.exist?(dst)
    end
  end
end
