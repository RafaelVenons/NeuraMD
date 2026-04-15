require "rails_helper"

RSpec.describe Mfa::AlignService do
  let(:note) { create(:note, :with_head_revision) }
  let(:asset) do
    a = create(:note_tts_asset, note_revision: note.head_revision, language: "en-US")
    a.audio.attach(io: StringIO.new("fake-wav-data"), filename: "test.wav", content_type: "audio/wav")
    a
  end

  let(:executor) { instance_double(Mfa::RemoteExecutor) }
  let(:mfa_output_json) do
    {
      "tiers" => {
        "words" => {
          "type" => "words",
          "entries" => [
            [0.0, 0.45, "hello"],
            [0.50, 0.92, "world"],
            [0.92, 1.0, ""]
          ]
        }
      }
    }
  end

  let(:output_dir) { File.join(described_class::MFA_OUTPUT_ROOT, asset.id.to_s) }
  let(:output_file) { File.join(output_dir, "audio.json") }

  before do
    allow(Mfa::RemoteExecutor).to receive(:new).and_return(executor)
    allow(executor).to receive(:execute)
    allow(executor).to receive(:push_dir)
    allow(executor).to receive(:pull_dir)
    allow(executor).to receive(:execute_host_cleanup)
    # Stub filesystem operations so we don't need ffmpeg or real files
    allow_any_instance_of(described_class).to receive(:prepare_input)
    allow_any_instance_of(described_class).to receive(:cleanup)
  end

  describe ".call" do
    before do
      allow(File).to receive(:exist?).and_call_original
      allow(File).to receive(:exist?).with(output_file).and_return(true)
      allow(File).to receive(:read).and_call_original
      allow(File).to receive(:read).with(output_file).and_return(mfa_output_json.to_json)
      allow(FileUtils).to receive(:mkdir_p)
      allow(File).to receive(:write)
    end

    it "runs alignment and stores result in the asset" do
      described_class.call(asset)

      asset.reload
      expect(asset.alignment_status).to eq("succeeded")
      expect(asset.alignment_data["words"].length).to eq(2)
      expect(asset.alignment_data["words"][0]).to eq({"word" => "hello", "start" => 0.0, "end" => 0.45})
      expect(asset.alignment_data["words"][1]).to eq({"word" => "world", "start" => 0.5, "end" => 0.92})
      expect(asset.alignment_data["duration_s"]).to eq(0.92)
    end

    it "calls execute with MFA align command" do
      described_class.call(asset)

      expect(executor).to have_received(:execute).with(
        a_string_matching(/mfa align.*english_mfa.*--output_format json/)
      )
    end

    it "skips empty words in alignment output" do
      described_class.call(asset)

      asset.reload
      words = asset.alignment_data["words"]
      expect(words.map { |w| w["word"] }).to eq(%w[hello world])
    end

    context "when AiRequest has original text" do
      let!(:ai_request) do
        create(:ai_request,
          note_revision: note.head_revision,
          capability: "tts",
          input_text: "Hello World!",
          metadata: {"tts_asset_id" => asset.id.to_s}
        )
      end

      it "preserves original casing and punctuation in alignment words" do
        described_class.call(asset)

        asset.reload
        words = asset.alignment_data["words"]
        expect(words.map { |w| w["word"] }).to eq(%w[Hello World!])
      end
    end

    context "when MFA splits compound words" do
      let(:mfa_output_json) do
        {
          "tiers" => {
            "words" => {
              "type" => "words",
              "entries" => [
                [0.0, 0.3, "saude"],
                [0.3, 0.5, "e"],
                [0.5, 0.7, "bem"],
                [0.7, 1.0, "estar"]
              ]
            }
          }
        }
      end

      let!(:ai_request) do
        create(:ai_request,
          note_revision: note.head_revision,
          capability: "tts",
          input_text: "saúde e bem-estar",
          metadata: {"tts_asset_id" => asset.id.to_s}
        )
      end

      it "merges split parts back into the original compound word" do
        described_class.call(asset)

        asset.reload
        words = asset.alignment_data["words"]
        expect(words.map { |w| w["word"] }).to eq(%w[saúde e bem-estar])
        # Merged word should span the full timing range
        merged = words.find { |w| w["word"] == "bem-estar" }
        expect(merged["start"]).to eq(0.5)
        expect(merged["end"]).to eq(1.0)
      end
    end

    it "saves alignment JSON to shared filesystem" do
      json_dest = File.join(described_class::ALIGNMENT_ROOT, "json", "#{asset.id}.json")

      described_class.call(asset)

      expect(File).to have_received(:write).with(json_dest, anything)
    end
  end

  describe "validation" do
    it "raises ConfigurationError for unsupported language" do
      asset.update!(language: "xx-XX")
      expect { described_class.call(asset) }.to raise_error(Mfa::ConfigurationError, /Unsupported language/)
    end

    it "raises ConfigurationError when audio not attached" do
      asset.audio.purge
      allow_any_instance_of(described_class).to receive(:prepare_input).and_call_original
      expect { described_class.call(asset) }.to raise_error(Mfa::ConfigurationError, /no audio/)
    end
  end
end
