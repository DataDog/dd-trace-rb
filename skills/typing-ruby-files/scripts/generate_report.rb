#!/usr/bin/env ruby
# typed: false
# frozen_string_literal: true

require "json"
require "fileutils"
require "optparse"
require "time"

REQUIRED_COMPROMISE_KEYS = %w[offence cause chosen_solution evidence].freeze

def load_json(path)
  JSON.parse(File.read(path))
end

def write_text(path, text)
  FileUtils.mkdir_p(File.dirname(path))
  File.write(path, text)
end

def write_json(path, payload)
  FileUtils.mkdir_p(File.dirname(path))
  File.write(path, JSON.pretty_generate(payload) + "\n")
end

def normalize_compromises(compromises_data)
  compromises_data.each_with_index.map do |item, index|
    missing = REQUIRED_COMPROMISE_KEYS.reject { |key| item.key?(key) }
    unless missing.empty?
      raise ArgumentError, "compromise ##{index + 1} missing required keys: #{missing.join(', ')}"
    end

    {
      "offence" => item["offence"],
      "cause" => item["cause"],
      "chosen_solution" => item["chosen_solution"],
      "evidence" => item["evidence"]
    }
  end
end

def build_report(scope:, before:, after:, steep:, runtime_lib_edits:, targeted_tests_command:, targeted_tests_result:, compromises:)
  stale_targets = Array(scope["stale_targets"])
  missing_sig = Array(scope["missing_sig"])
  normal = steep.fetch("runs").fetch("normal")
  information = steep.fetch("runs").fetch("information")

  runtime_required = !runtime_lib_edits.empty?
  runtime_gate_ok = true
  runtime_gate_reason = "not required"

  if runtime_required
    if targeted_tests_command.to_s.empty? || targeted_tests_result.to_s.empty?
      runtime_gate_ok = false
      runtime_gate_reason = "runtime lib edits present but targeted test metadata is missing"
    elsif targeted_tests_result != "pass"
      runtime_gate_ok = false
      runtime_gate_reason = "targeted tests did not pass (result=#{targeted_tests_result})"
    else
      runtime_gate_reason = "targeted tests passed"
    end
  end

  gate_pass =
    stale_targets.empty? &&
      missing_sig.empty? &&
      normal.fetch("exit_code").zero? &&
      information.fetch("exit_code").zero? &&
      runtime_gate_ok

  {
    "generated_at" => Time.now.utc.iso8601(6),
    "gate_pass" => gate_pass,
    "scope" => {
      "targets" => Array(scope["targets"]),
      "stale_targets" => stale_targets,
      "missing_sig" => missing_sig,
      "steep_targets" => Array(scope["steep_targets"])
    },
    "untyped" => {
      "before_total" => before.fetch("total_untyped", 0),
      "after_total" => after.fetch("total_untyped", 0),
      "delta" => after.fetch("total_untyped", 0) - before.fetch("total_untyped", 0),
      "post_edit_inventory" => Array(after["inventory"]),
      "delta_details" => after["delta"]
    },
    "steep" => {
      "normal_exit_code" => normal.fetch("exit_code"),
      "information_exit_code" => information.fetch("exit_code"),
      "normal_diagnostics" => Array(normal["diagnostics"]),
      "information_diagnostics" => Array(information["diagnostics"])
    },
    "runtime_behavior_tests" => {
      "required" => runtime_required,
      "runtime_lib_edits" => runtime_lib_edits,
      "command" => targeted_tests_command,
      "result" => targeted_tests_result,
      "gate_ok" => runtime_gate_ok,
      "reason" => runtime_gate_reason
    },
    "compromises" => compromises
  }
end

def markdown_for_report(report)
  scope = report.fetch("scope")
  untyped = report.fetch("untyped")
  steep = report.fetch("steep")
  tests = report.fetch("runtime_behavior_tests")
  compromises = report.fetch("compromises")

  lines = []
  lines << "# Typing Report"
  lines << ""
  lines << "- generated_at: `#{report.fetch('generated_at')}`"
  lines << "- gate_pass: `#{report.fetch('gate_pass')}`"
  lines << ""
  lines << "## Scope"
  lines << ""
  lines << "- targets: `#{scope.fetch('targets').length}`"
  lines << "- stale_targets: `#{scope.fetch('stale_targets').length}`"
  lines << "- missing_sig: `#{scope.fetch('missing_sig').length}`"
  lines << "- steep_targets: `#{scope.fetch('steep_targets').length}`"
  lines << ""

  unless scope.fetch("stale_targets").empty?
    lines << "### Stale Targets"
    lines << ""
    scope.fetch("stale_targets").each { |path| lines << "- `#{path}`" }
    lines << ""
  end

  unless scope.fetch("missing_sig").empty?
    lines << "### Missing Signatures"
    lines << ""
    scope.fetch("missing_sig").each { |path| lines << "- `#{path}`" }
    lines << ""
  end

  lines << "## Untyped Delta"
  lines << ""
  lines << "- before_total: `#{untyped.fetch('before_total')}`"
  lines << "- after_total: `#{untyped.fetch('after_total')}`"
  lines << "- delta: `#{untyped.fetch('delta')}`"
  lines << ""
  lines << "### Post-Edit Untyped Inventory"
  lines << ""
  if untyped.fetch("post_edit_inventory").empty?
    lines << "- none"
  else
    untyped.fetch("post_edit_inventory").each do |entry|
      lines << "- `#{entry.fetch('sig_path')}:#{entry.fetch('line')}` #{entry.fetch('line_text')}"
    end
  end
  lines << ""

  lines << "## Steep Results"
  lines << ""
  lines << "- normal_exit_code: `#{steep.fetch('normal_exit_code')}`"
  lines << "- information_exit_code: `#{steep.fetch('information_exit_code')}`"
  lines << "- normal_diagnostics: `#{steep.fetch('normal_diagnostics').length}`"
  lines << "- information_diagnostics: `#{steep.fetch('information_diagnostics').length}`"
  lines << ""

  lines << "## Runtime Behavior Tests"
  lines << ""
  lines << "- required: `#{tests.fetch('required')}`"
  lines << "- gate_ok: `#{tests.fetch('gate_ok')}`"
  lines << "- reason: `#{tests.fetch('reason')}`"
  unless tests.fetch("runtime_lib_edits").empty?
    lines << "- runtime_lib_edits:"
    tests.fetch("runtime_lib_edits").each { |path| lines << "  - `#{path}`" }
  end
  lines << "- command: `#{tests.fetch('command')}`" if tests["command"]
  lines << "- result: `#{tests.fetch('result')}`" if tests["result"]
  lines << ""

  lines << "## Compromises"
  lines << ""
  if compromises.empty?
    lines << "- none"
    lines << ""
    return lines.join("\n")
  end

  compromises.each_with_index do |compromise, index|
    lines << "### Compromise #{index + 1}"
    lines << ""
    lines << "- offence: #{compromise.fetch('offence')}"
    lines << "- cause: #{compromise.fetch('cause')}"
    lines << "- chosen_solution: #{compromise.fetch('chosen_solution')}"
    evidence = compromise.fetch("evidence")
    lines << if evidence.is_a?(Hash)
      "- evidence: `#{JSON.generate(evidence.sort.to_h)}`"
    else
      "- evidence: #{evidence}"
    end
    lines << ""
  end

  lines.join("\n")
end

options = {
  runtime_lib_edits: []
}

parser = OptionParser.new do |opts|
  opts.banner = "Usage: generate_report.rb --scope scope.json --before before.json --after after.json --steep steep.json --out-md report.md --out-json report.json"

  opts.on("--scope PATH", "Path to scope JSON") { |value| options[:scope] = value }
  opts.on("--before PATH", "Path to pre-edit untyped JSON") { |value| options[:before] = value }
  opts.on("--after PATH", "Path to post-edit untyped JSON") { |value| options[:after] = value }
  opts.on("--steep PATH", "Path to steep JSON") { |value| options[:steep] = value }
  opts.on("--out-md PATH", "Markdown report output path") { |value| options[:out_md] = value }
  opts.on("--out-json PATH", "JSON report output path") { |value| options[:out_json] = value }
  opts.on("--runtime-lib-edit PATH", "Edited runtime lib path, repeatable") do |value|
    options[:runtime_lib_edits] << value
  end
  opts.on("--targeted-tests-command VALUE", "Exact targeted test command used when runtime lib edits are present") do |value|
    options[:targeted_tests_command] = value
  end
  opts.on("--targeted-tests-result VALUE", "Targeted test result: pass|fail|skipped") do |value|
    options[:targeted_tests_result] = value
  end
  opts.on("--compromises-json PATH", "Optional JSON file containing compromise entries") do |value|
    options[:compromises_json] = value
  end
end

begin
  parser.parse!
rescue OptionParser::ParseError => e
  warn "[ERROR] #{e.message}"
  warn parser
  exit 1
end

required = %i[scope before after steep out_md out_json]
missing = required.reject { |key| options[key] }
unless missing.empty?
  missing.each { |key| warn "[ERROR] --#{key.to_s.tr('_', '-')} is required" }
  warn parser
  exit 1
end

if options[:targeted_tests_result] && !%w[pass fail skipped].include?(options[:targeted_tests_result])
  warn "[ERROR] --targeted-tests-result must be one of: pass, fail, skipped"
  exit 1
end

scope = load_json(options[:scope])
before = load_json(options[:before])
after = load_json(options[:after])
steep = load_json(options[:steep])

compromises = []
if options[:compromises_json]
  raw = load_json(options[:compromises_json])
  unless raw.is_a?(Array)
    warn "[ERROR] compromises JSON must contain a list"
    exit 3
  end

  begin
    compromises = normalize_compromises(raw)
  rescue ArgumentError => e
    warn "[ERROR] #{e.message}"
    exit 4
  end
end

report = build_report(
  scope: scope,
  before: before,
  after: after,
  steep: steep,
  runtime_lib_edits: options[:runtime_lib_edits].uniq.sort,
  targeted_tests_command: options[:targeted_tests_command],
  targeted_tests_result: options[:targeted_tests_result],
  compromises: compromises
)

markdown = markdown_for_report(report)
markdown = "#{markdown}\n" unless markdown.end_with?("\n")

write_text(options[:out_md], markdown)
write_json(options[:out_json], report)

puts "[OK] wrote markdown report: #{options[:out_md]}"
puts "[OK] wrote json report: #{options[:out_json]}"
puts "[INFO] gate_pass=#{report.fetch('gate_pass')}"

exit(report.fetch("gate_pass") ? 0 : 2)
