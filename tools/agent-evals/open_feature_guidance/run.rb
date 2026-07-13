# frozen_string_literal: true

require 'json'
require 'open3'
require 'optparse'
require 'tmpdir'

ROOT = File.expand_path('../../..', __dir__)
CASES_DIR = File.join(__dir__, 'cases')
OUTPUT_SCHEMA = File.join(__dir__, 'output.schema.json')

options = {cases: [], model: nil}
OptionParser.new do |parser|
  parser.banner = 'Usage: ruby tools/agent-evals/open_feature_guidance/run.rb [options]'
  parser.on('--case NAME', 'Run one named case (repeatable)') { |name| options[:cases] << name }
  parser.on('--model MODEL', 'Pass a model override to codex exec') { |model| options[:model] = model }
end.parse!

case_paths =
  if options[:cases].empty?
    Dir[File.join(CASES_DIR, '*.json')].sort
  else
    options[:cases].map { |name| File.join(CASES_DIR, "#{name}.json") }
  end

missing_case_paths = case_paths.reject { |path| File.file?(path) }
unless missing_case_paths.empty?
  warn "Unknown eval case(s): #{missing_case_paths.map { |path| File.basename(path, '.json') }.join(', ')}"
  exit 2
end

def run_codex(prompt, output_path, model)
  command = [
    'codex', 'exec',
    '--ephemeral',
    '--ignore-user-config',
    '--sandbox', 'read-only',
    '--color', 'never',
    '--cd', ROOT,
    '--output-schema', OUTPUT_SCHEMA,
    '--output-last-message', output_path,
  ]
  command.concat(['--model', model]) if model
  command << prompt

  Open3.capture3(*command, chdir: ROOT)
end

def evaluate(case_config, result)
  instruction_files = result.fetch('instruction_files')
  answer = result.fetch('answer')

  missing_files = case_config.fetch('expected_instruction_files').reject do |path|
    instruction_files.include?(path)
  end
  missing_fragments = case_config.fetch('required_answer_fragments').reject do |fragment|
    answer.downcase.include?(fragment.downcase)
  end

  [missing_files, missing_fragments]
end

failures = []

case_paths.each do |case_path|
  case_config = JSON.parse(File.read(case_path))
  name = case_config.fetch('name')

  Dir.mktmpdir("open-feature-agent-eval-#{name}") do |tmpdir|
    output_path = File.join(tmpdir, 'result.json')
    stdout, stderr, status = run_codex(case_config.fetch('prompt'), output_path, options[:model])

    unless status.success?
      failures << [name, "codex exec failed (#{status.exitstatus})\n#{stderr}\n#{stdout}"]
      next
    end

    begin
      result = JSON.parse(File.read(output_path))
      missing_files, missing_fragments = evaluate(case_config, result)
    rescue JSON::ParserError, KeyError, Errno::ENOENT => e
      failures << [name, "invalid structured result: #{e.message}"]
      next
    end

    if missing_files.empty? && missing_fragments.empty?
      puts "PASS #{name}"
    else
      details = []
      details << "missing instruction files: #{missing_files.join(', ')}" unless missing_files.empty?
      details << "missing answer fragments: #{missing_fragments.join(', ')}" unless missing_fragments.empty?
      details << "result: #{JSON.pretty_generate(result)}"
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
