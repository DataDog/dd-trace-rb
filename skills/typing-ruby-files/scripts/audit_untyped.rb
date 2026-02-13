#!/usr/bin/env ruby
# typed: false
# frozen_string_literal: true

require "json"
require "fileutils"
require "optparse"
require "set"
require "time"

UNTYPED_PATTERN = /\buntyped\b/.freeze

def load_json(path)
  JSON.parse(File.read(path))
end

def write_json(path, payload)
  FileUtils.mkdir_p(File.dirname(path))
  File.write(path, JSON.pretty_generate(payload) + "\n")
end

def inventory_untyped(scope, allow_missing_sig:)
  missing_sig = Array(scope["missing_sig"])
  if !allow_missing_sig && !missing_sig.empty?
    warn "[ERROR] cannot audit untyped because signature files are missing:"
    missing_sig.each { |path| warn "  - #{path}" }
    return [nil, 3]
  end

  entries = []
  file_counts = Hash.new(0)

  Array(scope["mappings"]).each do |mapping|
    sig_path = mapping["sig_path"]
    next unless mapping["sig_exists"]
    next unless sig_path && File.file?(sig_path)

    File.readlines(sig_path, chomp: true).each_with_index do |line, index|
      next unless UNTYPED_PATTERN.match?(line)

      entries << {
        "sig_path" => sig_path,
        "line" => index + 1,
        "line_text" => line.strip
      }
      file_counts[sig_path] += 1
    end
  end

  entries.sort_by! { |entry| [entry["sig_path"], entry["line"]] }

  [
    {
      "generated_at" => Time.now.utc.iso8601(6),
      "phase" => nil,
      "total_untyped" => entries.length,
      "file_counts" => file_counts.sort.to_h,
      "inventory" => entries
    },
    0
  ]
end

def apply_delta!(after_payload, before_payload)
  after_points = after_payload.fetch("inventory").map { |entry| [entry["sig_path"], entry["line"]] }.to_set
  before_points = before_payload.fetch("inventory").map { |entry| [entry["sig_path"], entry["line"]] }.to_set

  added = (after_points - before_points).to_a.sort
  removed = (before_points - after_points).to_a.sort
  unchanged = (after_points & before_points).to_a

  after_payload["delta"] = {
    "before_total" => before_payload.fetch("total_untyped"),
    "after_total" => after_payload.fetch("total_untyped"),
    "change" => after_payload.fetch("total_untyped") - before_payload.fetch("total_untyped"),
    "added" => added.map { |path, line| { "sig_path" => path, "line" => line } },
    "removed" => removed.map { |path, line| { "sig_path" => path, "line" => line } },
    "unchanged_count" => unchanged.length
  }
end

options = {
  allow_missing_sig: false
}

parser = OptionParser.new do |opts|
  opts.banner = "Usage: audit_untyped.rb --scope scope.json --phase before|after --out out.json [--baseline before.json]"

  opts.on("--scope PATH", "Path to scope JSON") { |value| options[:scope] = value }
  opts.on("--phase VALUE", "Phase: before or after") { |value| options[:phase] = value }
  opts.on("--out PATH", "Output JSON path") { |value| options[:out] = value }
  opts.on("--baseline PATH", "Baseline audit JSON path for delta computation") do |value|
    options[:baseline] = value
  end
  opts.on("--allow-missing-sig", "Allow missing signature files in scope") do
    options[:allow_missing_sig] = true
  end
end

begin
  parser.parse!
rescue OptionParser::ParseError => e
  warn "[ERROR] #{e.message}"
  warn parser
  exit 1
end

unless %w[before after].include?(options[:phase])
  warn "[ERROR] --phase must be one of: before, after"
  warn parser
  exit 1
end

%i[scope out].each do |key|
  next if options[key]

  warn "[ERROR] --#{key.to_s.tr('_', '-')} is required"
  warn parser
  exit 1
end

scope = load_json(options[:scope])
payload, exit_code = inventory_untyped(scope, allow_missing_sig: options[:allow_missing_sig])
exit exit_code if exit_code != 0

payload["phase"] = options[:phase]

if options[:baseline]
  baseline = load_json(options[:baseline])
  apply_delta!(payload, baseline)
end

write_json(options[:out], payload)

puts "[OK] wrote untyped audit JSON: #{options[:out]}"
puts "[INFO] phase=#{options[:phase]}"
puts "[INFO] total_untyped=#{payload.fetch("total_untyped")}"
if payload.key?("delta")
  puts "[INFO] delta=#{payload.fetch("delta").fetch("change")}"
end
