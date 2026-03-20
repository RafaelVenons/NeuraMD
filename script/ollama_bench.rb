#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "net/http"
require "optparse"
require "uri"

DEFAULT_BASE_URL = ENV.fetch("OLLAMA_API_BASE", "http://AIrch:11434")
DEFAULT_OPEN_TIMEOUT = Integer(ENV.fetch("OLLAMA_OPEN_TIMEOUT", "5"))
DEFAULT_READ_TIMEOUT = Integer(ENV.fetch("OLLAMA_READ_TIMEOUT", "180"))
DEFAULT_WRITE_TIMEOUT = Integer(ENV.fetch("OLLAMA_WRITE_TIMEOUT", "30"))
DEFAULT_NUM_PREDICT = Integer(ENV.fetch("OLLAMA_BENCH_NUM_PREDICT", "96"))

TASKS = {
  "grammar_review" => {
    prompt: "Return only the corrected sentence in pt-BR: Eu vai amanha no medico.",
    expected: "Eu vou ao médico amanhã."
  },
  "suggest" => {
    prompt: "Improve clarity and flow in pt-BR. Return only the revised text: O paciente falou que estava meio ruim, mas dai melhorou um pouco depois.",
    expected: nil
  },
  "rewrite" => {
    prompt: "Rewrite in pt-BR, preserving meaning and keeping it concise. Return only the rewritten text: A equipe decidiu fazer uma nova tentativa mais tarde porque o servidor ainda estava muito lento.",
    expected: nil
  },
  "translate_pt_en" => {
    prompt: "Translate to English. Return only the translation: O paciente melhorou depois do ajuste da medicação.",
    expected: "The patient improved after the medication adjustment."
  },
  "translate_en_pt" => {
    prompt: "Translate to pt-BR. Return only the translation: The server remained unstable during the afternoon, so the team postponed the deployment.",
    expected: "O servidor permaneceu instável durante a tarde, então a equipe adiou a implantação."
  },
  "translate_pt_es" => {
    prompt: "Translate to Spanish. Return only the translation: A equipe médica confirmou alta para amanhã de manhã.",
    expected: "El equipo médico confirmó el alta para mañana por la mañana."
  }
}.freeze

options = {
  base_url: DEFAULT_BASE_URL,
  open_timeout: DEFAULT_OPEN_TIMEOUT,
  read_timeout: DEFAULT_READ_TIMEOUT,
  write_timeout: DEFAULT_WRITE_TIMEOUT,
  num_predict: DEFAULT_NUM_PREDICT,
  tasks: TASKS.keys,
  models: nil
}

OptionParser.new do |parser|
  parser.banner = "Usage: ruby script/ollama_bench.rb [options]"

  parser.on("--base-url URL", "Ollama base URL") { |value| options[:base_url] = value }
  parser.on("--models x,y,z", Array, "Restrict benchmark to specific models") { |value| options[:models] = value }
  parser.on("--tasks x,y,z", Array, "Tasks: #{TASKS.keys.join(', ')}") { |value| options[:tasks] = value }
  parser.on("--num-predict N", Integer, "num_predict option for Ollama") { |value| options[:num_predict] = value }
  parser.on("--open-timeout N", Integer, "HTTP open timeout in seconds") { |value| options[:open_timeout] = value }
  parser.on("--read-timeout N", Integer, "HTTP read timeout in seconds") { |value| options[:read_timeout] = value }
  parser.on("--write-timeout N", Integer, "HTTP write timeout in seconds") { |value| options[:write_timeout] = value }
end.parse!

options[:tasks].each do |task|
  abort("Unknown task: #{task}") unless TASKS.key?(task)
end

def build_http(uri, options)
  Net::HTTP.new(uri.host, uri.port).tap do |http|
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = options[:open_timeout]
    http.read_timeout = options[:read_timeout]
    http.write_timeout = options[:write_timeout]
  end
end

def post_json(path, body, options)
  uri = URI.join(options[:base_url], path)
  http = build_http(uri, options)
  request = Net::HTTP::Post.new(uri)
  request["Content-Type"] = "application/json"
  request.body = JSON.generate(body)
  response = http.request(request)
  raise "HTTP #{response.code}: #{response.body}" unless response.is_a?(Net::HTTPSuccess)

  JSON.parse(response.body)
end

def get_json(path, options)
  uri = URI.join(options[:base_url], path)
  http = build_http(uri, options)
  request = Net::HTTP::Get.new(uri)
  response = http.request(request)
  raise "HTTP #{response.code}: #{response.body}" unless response.is_a?(Net::HTTPSuccess)

  JSON.parse(response.body)
end

def normalize_text(text)
  text.to_s
    .downcase
    .tr("áàâãäéèêëíìîïóòôõöúùûüç", "aaaaaeeeeiiiiooooouuuuc")
    .gsub(/[^a-z0-9\s]/, " ")
    .gsub(/\s+/, " ")
    .strip
end

def quality_label(task_name, response_text, expected)
  return "empty" if response_text.to_s.strip.empty?
  return "thinking-only" if response_text.to_s.include?("Thinking Process")
  return "ok" if expected.nil?

  normalize_text(response_text) == normalize_text(expected) ? "exact" : "usable"
end

all_models = get_json("/api/tags", options)
  .fetch("models")
  .map { |entry| entry.fetch("name") }
  .reject { |name| name.include?("embedding") }
models = options[:models] || all_models

results = []

models.each do |model|
  options[:tasks].each do |task_name|
    task = TASKS.fetch(task_name)
    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    response = post_json(
      "/api/generate",
      {
        model: model,
        prompt: task.fetch(:prompt),
        stream: false,
        options: {
          num_predict: options[:num_predict]
        }
      },
      options
    )
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at
    response_text = response["response"].to_s
    quality = quality_label(task_name, response_text, task[:expected])

    results << {
      model: model,
      task: task_name,
      elapsed_s: elapsed.round(2),
      total_duration_s: (response["total_duration"].to_f / 1_000_000_000).round(2),
      eval_count: response["eval_count"],
      done_reason: response["done_reason"],
      quality: quality,
      sample: response_text.gsub(/\s+/, " ").strip[0, 120]
    }
  rescue StandardError => error
    results << {
      model: model,
      task: task_name,
      elapsed_s: nil,
      total_duration_s: nil,
      eval_count: nil,
      done_reason: "error",
      quality: "error",
      sample: error.message[0, 120]
    }
  end
end

puts JSON.pretty_generate(results: results)

puts
puts "| Model | Task | Quality | Time (s) | Ollama Time (s) | Done | Sample |"
puts "| --- | --- | --- | ---: | ---: | --- | --- |"
results.each do |result|
  puts [
    "| #{result[:model]}",
    result[:task],
    result[:quality],
    result[:elapsed_s] || "—",
    result[:total_duration_s] || "—",
    result[:done_reason],
    result[:sample].to_s.gsub("|", "/"),
    "|"
  ].join(" ")
end
