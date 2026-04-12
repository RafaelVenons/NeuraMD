# frozen_string_literal: true

# Benchmark TOC-detection across LLM providers as a potential fallback
# for the Ruby FileImports::TocDetector.
#
# Usage:
#   bin/rails ai:toc_benchmark                # all fixtures, all models
#   PDF=Luger bin/rails ai:toc_benchmark      # only PDFs matching substring
#   MODELS=qwen3.5:4b bin/rails ai:toc_benchmark
#
# Reads from /tmp/import-cache/*.md produced by `bin/test-import`. If cache is
# cold for a file, falls back to live conversion (slow).
namespace :ai do
  desc "Compare LLMs at detecting TOC anchor+entries in converted PDF markdown"
  task toc_benchmark: :environment do
    require "digest"
    require "json"
    require "net/http"
    $stdout.sync = true

    fixtures = Dir.glob(Rails.root.join("spec/fixtures/files/*.pdf").to_s).sort
    if ENV["PDF"].present?
      pattern = ENV["PDF"].downcase
      fixtures = fixtures.select { |p| File.basename(p).downcase.include?(pattern) }
    end

    if fixtures.empty?
      puts "No PDFs matched."
      exit 1
    end

    models = TocBenchmark.models_to_test
    if models.empty?
      puts "No models configured. Check AI_ENABLED_PROVIDERS."
      exit 1
    end

    puts "=" * 90
    puts "TOC-detection LLM benchmark — #{Time.current.strftime("%Y-%m-%d %H:%M")}"
    puts "PDFs:   #{fixtures.size}"
    puts "Models: #{models.map { |m| "#{m[:host]}/#{m[:model]}" }.join(", ")}"
    puts "=" * 90

    results = []

    fixtures.each do |pdf|
      name = File.basename(pdf)
      puts "\n── #{name} ".ljust(90, "─")
      markdown = TocBenchmark.load_or_convert(pdf)
      head = TocBenchmark.extract_head(markdown)
      puts "  head: #{head.lines.size} lines, #{head.bytesize} bytes"

      ruby = FileImports::TocDetector.call(markdown: markdown)
      if ruby
        puts "  ruby:   anchor=#{ruby[:anchor_kind].inspect} line=#{ruby[:anchor_line]} entries=#{ruby[:entries].size}"
      else
        puts "  ruby:   NOT DETECTED"
      end

      models.each do |m|
        r = TocBenchmark.ask(m, head)
        r[:pdf] = name
        results << r
        TocBenchmark.print_row(r)
      end
    end

    puts "\n#{"=" * 90}"
    puts "SUMMARY"
    puts "=" * 90
    TocBenchmark.print_summary(results)
  end
end

module TocBenchmark
  module_function

  CACHE_DIR = "/tmp/import-cache"
  HEAD_LINES = 400  # enough to cover preface + TOC in all tested PDFs
  SYSTEM_PROMPT = <<~PROMPT.freeze
    You analyze the head of a markdown document converted from a PDF. Your job is
    to locate the Table of Contents (TOC), if any, and list its top-level entries.

    Respond with STRICT JSON only, no prose, matching this schema:
    {
      "anchor_found": bool,
      "anchor_line": int | null,        // 1-based line number of the TOC heading
      "anchor_text": string | null,     // e.g. "Contents", "Sumário"
      "entries": [                      // top-level entries only (chapters/parts)
        {"number": string | null, "title": string, "level": int}
      ]
    }

    Rules:
    - "TOC" means a heading literally named one of: Contents, Table of Contents,
      Brief Contents, Sumário, Sumario, Índice, Indice. Case-insensitive.
    - If the document has both "Brief Contents" and "Contents", prefer "Contents".
    - List only top-level chapters/parts. Skip subsections (1.1, 1.2).
    - Skip boilerplate like Cover, Title Page, Capa, Folha de Rosto, Preface, Index.
    - If no TOC, return {"anchor_found": false, "anchor_line": null, "anchor_text": null, "entries": []}.
  PROMPT

  def models_to_test
    models = []
    selected = (ENV["MODELS"] || "").split(",").map(&:strip).reject(&:empty?)

    provider_names = ENV.fetch("AI_ENABLED_PROVIDERS", "ollama,ollama_bazzite")
      .split(",").map(&:strip)

    provider_names.each do |provider_name|
      config = Ai::ProviderRegistry.send(:provider_config, provider_name)
      next if config[:base_url].blank?
      available = Ai::OllamaProvider.available_models(base_url: config[:base_url])
      available.each do |m|
        next if selected.any? && selected.none? { |s| m.include?(s) }
        models << { host: provider_name, base_url: config[:base_url], model: m }
      end
    rescue => e
      warn "skip #{provider_name}: #{e.message}"
    end

    models
  end

  def load_or_convert(path)
    stat = File.stat(path)
    key = Digest::SHA256.hexdigest("#{File.expand_path(path)}|#{stat.size}|#{stat.mtime.to_i}")
    cache = File.join(CACHE_DIR, "#{key}.md")
    if File.exist?(cache)
      File.read(cache)
    else
      puts "  (cache miss — converting, this takes minutes)"
      FileUtils.mkdir_p(CACHE_DIR)
      md = FileImports::ConvertService.call(file_path: path)
      File.write(cache, md)
      md
    end
  end

  def extract_head(markdown)
    markdown.lines.first(HEAD_LINES).join
  end

  def ask(model_cfg, head)
    body = {
      model: model_cfg[:model],
      stream: false,
      format: "json",
      messages: [
        { role: "system", content: SYSTEM_PROMPT },
        { role: "user", content: head }
      ],
      options: { temperature: 0.0, num_ctx: 16_384 }
    }
    body[:think] = false if model_cfg[:model].start_with?("qwen3")

    t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    response = http_post_json("#{model_cfg[:base_url]}/api/chat", body)
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0

    content = response.dig("message", "content").to_s
    parsed = safe_json(content)
    entries = parsed["entries"].is_a?(Array) ? parsed["entries"] : []

    {
      host: model_cfg[:host], model: model_cfg[:model],
      elapsed: elapsed.round(2),
      tokens_out: response["eval_count"].to_i,
      anchor: parsed["anchor_text"],
      anchor_line: parsed["anchor_line"],
      entries_count: entries.size,
      sample: entries.first(3).map { |e| e["title"] }.join(" | "),
      status: parsed["anchor_found"] ? :ok : :no_toc,
      raw: content.truncate(400)
    }
  rescue => e
    {
      host: model_cfg[:host], model: model_cfg[:model],
      elapsed: 0.0, tokens_out: 0,
      anchor: nil, anchor_line: nil, entries_count: 0,
      sample: "ERROR: #{e.message.truncate(80)}",
      status: :error, raw: ""
    }
  end

  def http_post_json(url, body)
    uri = URI.parse(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = 10
    http.read_timeout = 300
    req = Net::HTTP::Post.new(uri.request_uri, "Content-Type" => "application/json")
    req.body = body.to_json
    res = http.request(req)
    raise "HTTP #{res.code}: #{res.body.to_s.truncate(200)}" unless res.is_a?(Net::HTTPSuccess)
    JSON.parse(res.body)
  end

  def safe_json(str)
    JSON.parse(str)
  rescue JSON::ParserError
    {}
  end

  def print_row(r)
    icon = { ok: "OK  ", no_toc: "nil ", error: "FAIL" }[r[:status]]
    printf "  %-4s %-25s %5.1fs tok:%-5d entries:%-3d anchor=%s\n",
      icon, "#{r[:host]}/#{r[:model]}", r[:elapsed], r[:tokens_out],
      r[:entries_count], (r[:anchor] || "—").to_s.truncate(20)
    puts "       sample: #{r[:sample].truncate(80)}" unless r[:sample].empty?
  end

  def print_summary(results)
    by_model = results.group_by { |r| "#{r[:host]}/#{r[:model]}" }
    by_model.each do |key, runs|
      oks = runs.count { |r| r[:status] == :ok }
      avg = (runs.sum { |r| r[:elapsed] } / runs.size).round(2)
      printf "  %-35s detected:%-3d/%-3d avg:%ss\n", key, oks, runs.size, avg
    end
  end
end
