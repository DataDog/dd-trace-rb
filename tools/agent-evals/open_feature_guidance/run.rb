# frozen_string_literal: true

require "json"
require "open3"
require "optparse"
require "tmpdir"

DEFAULT_ROOT = File.expand_path("../../..", __dir__)
CASES_DIR = File.join(__dir__, "cases")
OUTPUT_SCHEMA = File.join(__dir__, "output.schema.json")

options = {cases: [], model: nil, root: DEFAULT_ROOT}
OptionParser.new do |parser|
  parser.banner = "Usage: ruby tools/agent-evals/open_feature_guidance/run.rb [options]"
  parser.on("--case NAME", "Run one named case (repeatable)") { |name| options[:cases] << name }
  parser.on("--model MODEL", "Pass a model override to codex exec") { |model| options[:model] = model }
  parser.on("--root PATH", "Evaluate another repository checkout") { |root| options[:root] = root }
end.parse!

evaluation_root = File.expand_path(options[:root])
unless File.directory?(evaluation_root)
  warn "Unknown evaluation root: #{evaluation_root}"
  exit 2
end

case_paths =
  if options[:cases].empty?
    Dir[File.join(CASES_DIR, "*.json")].sort
  else
    options[:cases].map { |name| File.join(CASES_DIR, "#{name}.json") }
  end

missing_case_paths = case_paths.reject { |path| File.file?(path) }
unless missing_case_paths.empty?
  warn "Unknown eval case(s): #{missing_case_paths.map { |path| File.basename(path, ".json") }.join(", ")}"
  exit 2
end

def run_codex(prompt, output_path, model, root)
  command = [
    "codex", "exec",
    "--ephemeral",
    "--ignore-user-config",
    "--sandbox", "read-only",
    "--color", "never",
    "--cd", root,
    "--output-schema", OUTPUT_SCHEMA,
    "--output-last-message", output_path
  ]
  command.concat(["--model", model]) if model
  command << prompt

  Open3.capture3(*command, chdir: root)
end

def evaluate(case_config, result)
  instruction_files = result.fetch("instruction_files")

  case_config.fetch("expected_instruction_files").reject do |path|
    instruction_files.include?(path)
  end
end

failures = []

case_paths.each do |case_path|
  case_config = JSON.parse(File.read(case_path))
  name = case_config.fetch("name")

  Dir.mktmpdir("open-feature-agent-eval-#{name}") do |tmpdir|
    output_path = File.join(tmpdir, "result.json")
    stdout, stderr, status = run_codex(case_config.fetch("prompt"), output_path, options[:model], evaluation_root)

    unless status.success?
      failures << [name, "codex exec failed (#{status.exitstatus})\n#{stderr}\n#{stdout}"]
      next
    end

    begin
      result = JSON.parse(File.read(output_path))
      missing_files = evaluate(case_config, result)
    rescue JSON::ParserError, KeyError, Errno::ENOENT => e
      failures << [name, "invalid structured result: #{e.message}"]
      next
    end

    if missing_files.empty?
      puts "PASS #{name}"
    else
      details = [
        "missing instruction files: #{missing_files.join(", ")}",
        "result: #{JSON.pretty_generate(result)}",
      ]
      failures << [name, details.join("\n")]
    end
  end
end

unless failures.empty?
  failures.each do |name, details|
    warn "FAIL #{name}"
    warn details
  end
  exit 1
end

puts "#{case_paths.length} eval(s) passed"
