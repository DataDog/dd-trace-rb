#!/usr/bin/env ruby
# typed: false
# frozen_string_literal: true

require "json"
require "fileutils"
require "open3"
require "optparse"
require "shellwords"
require "time"

DIAGNOSTIC_WITH_COLUMN = /
  ^
  (?<file>[^:]+):
  (?<line>\d+):
  (?<column>\d+):
  \s\[(?<severity>[^\]]+)\]
  (?:\s\[(?<id>[^\]]+)\])?
  \s(?<message>.*)
  $
/x.freeze

DIAGNOSTIC_NO_COLUMN = /
  ^
  (?<file>[^:]+):
  (?<line>\d+):
  \s\[(?<severity>[^\]]+)\]
  (?:\s\[(?<id>[^\]]+)\])?
  \s(?<message>.*)
  $
/x.freeze

def load_json(path)
  JSON.parse(File.read(path))
end

def write_json(path, payload)
  FileUtils.mkdir_p(File.dirname(path))
  File.write(path, JSON.pretty_generate(payload) + "\n")
end

def parse_diagnostics(output)
  output.lines.filter_map do |line|
    text = line.chomp
    match = DIAGNOSTIC_WITH_COLUMN.match(text) || DIAGNOSTIC_NO_COLUMN.match(text)
    next unless match

    {
      "file" => match[:file],
      "line" => Integer(match[:line]),
      "column" => match[:column] ? Integer(match[:column]) : nil,
      "severity" => match[:severity],
      "diagnostic_id" => match[:id],
      "message" => match[:message]
    }
  end
end

def run_command(command)
  stdout, stderr, status = Open3.capture3(*command)
  combined = stdout + (stderr.empty? ? "" : "\n") + stderr
  diagnostics = parse_diagnostics(combined)
  {
    "command" => command,
    "exit_code" => status.exitstatus,
    "stdout" => stdout,
    "stderr" => stderr,
    "diagnostics" => diagnostics,
    "diagnostic_count" => diagnostics.length
  }
end

options = {
  bundle_cmd: "bundle exec",
  allow_failure: false
}

parser = OptionParser.new do |opts|
  opts.banner = "Usage: run_steep_checks.rb --scope scope.json --out steep.json [--bundle-cmd 'bundle exec'] [--allow-failure]"

  opts.on("--scope PATH", "Path to scope JSON") { |value| options[:scope] = value }
  opts.on("--out PATH", "Output JSON path") { |value| options[:out] = value }
  opts.on("--bundle-cmd VALUE", "Bundle command prefix, default: 'bundle exec'") do |value|
    options[:bundle_cmd] = value
  end
  opts.on("--allow-failure", "Return success even if steep exits non-zero") do
    options[:allow_failure] = true
  end
end

begin
  parser.parse!
rescue OptionParser::ParseError => e
  warn "[ERROR] #{e.message}"
  warn parser
  exit 1
end

%i[scope out].each do |key|
  next if options[key]

  warn "[ERROR] --#{key} is required"
  warn parser
  exit 1
end

scope = load_json(options[:scope])
steep_targets = Array(scope["steep_targets"])
if steep_targets.empty?
  warn "[ERROR] no steep targets found in scope JSON"
  exit 2
end

bundle_prefix = Shellwords.split(options[:bundle_cmd])
if bundle_prefix.empty?
  warn "[ERROR] --bundle-cmd produced an empty command prefix"
  exit 3
end

normal_cmd = bundle_prefix + ["steep", "check"] + steep_targets
info_cmd = bundle_prefix + ["steep", "check", "--severity-level=information"] + steep_targets

normal_result = run_command(normal_cmd)
info_result = run_command(info_cmd)

payload = {
  "generated_at" => Time.now.utc.iso8601(6),
  "steep_targets" => steep_targets,
  "runs" => {
    "normal" => normal_result,
    "information" => info_result
  }
}
write_json(options[:out], payload)

puts "[OK] wrote steep diagnostics JSON: #{options[:out]}"
puts "[INFO] normal_exit=#{normal_result.fetch("exit_code")} information_exit=#{info_result.fetch("exit_code")}"

failures = []
failures << "normal" if normal_result.fetch("exit_code") != 0
failures << "information" if info_result.fetch("exit_code") != 0

if !options[:allow_failure] && !failures.empty?
  warn "[ERROR] steep checks failed for: #{failures.join(', ')}"
  exit 4
end
