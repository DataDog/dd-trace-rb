#!/usr/bin/env ruby
# typed: false
# frozen_string_literal: true

require "json"
require "fileutils"
require "optparse"
require "pathname"
require "set"
require "time"

def normalize_target(raw)
  target = raw.strip
  target.start_with?("./") ? target.delete_prefix("./") : target
end

def validate_target!(target)
  raise ArgumentError, "target must be under lib/: #{target}" unless target.start_with?("lib/")
  raise ArgumentError, "target must be a Ruby file (*.rb): #{target}" unless target.end_with?(".rb")
end

def map_sig_path(lib_path)
  lib_rel = Pathname.new(lib_path).relative_path_from(Pathname.new("lib"))
  Pathname.new("sig").join(lib_rel).sub_ext(".rbs").to_s
end

def build_scope(targets)
  normalized = targets.map { |target| normalize_target(target) }.uniq.sort
  normalized.each { |target| validate_target!(target) }

  mappings = []
  stale_targets = []
  missing_sig = []
  steep_targets = Set.new

  normalized.each do |lib_path|
    lib_exists = File.file?(lib_path)
    sig_path = map_sig_path(lib_path)
    sig_exists = File.file?(sig_path)

    if lib_exists
      steep_targets << File.dirname(lib_path)
      missing_sig << sig_path unless sig_exists
    else
      stale_targets << lib_path
    end

    mappings << {
      "lib_path" => lib_path,
      "lib_exists" => lib_exists,
      "sig_path" => sig_path,
      "sig_exists" => sig_exists
    }
  end

  {
    "generated_at" => Time.now.utc.iso8601(6),
    "targets" => normalized,
    "mappings" => mappings,
    "stale_targets" => stale_targets.sort,
    "missing_sig" => missing_sig.sort,
    "steep_targets" => steep_targets.to_a.sort
  }
end

def write_json(path, payload)
  FileUtils.mkdir_p(File.dirname(path))
  File.write(path, JSON.pretty_generate(payload) + "\n")
end

options = {
  targets: [],
  allow_missing_sig: false
}

parser = OptionParser.new do |opts|
  opts.banner = "Usage: resolve_scope.rb --target lib/path.rb --out path.json [--allow-missing-sig]"

  opts.on("--target PATH", "Ruby target under lib/**/*.rb; repeat for multiple files") do |value|
    options[:targets] << value
  end
  opts.on("--out PATH", "Output JSON path") { |value| options[:out] = value }
  opts.on("--allow-missing-sig", "Do not fail when mapped signature files are missing") do
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

if options[:targets].empty?
  warn "[ERROR] at least one --target is required"
  warn parser
  exit 1
end

unless options[:out]
  warn "[ERROR] --out is required"
  warn parser
  exit 1
end

scope =
  begin
    build_scope(options[:targets])
  rescue ArgumentError => e
    warn "[ERROR] #{e.message}"
    exit 2
  end

write_json(options[:out], scope)

puts "[OK] wrote scope JSON: #{options[:out]}"
puts "[INFO] targets=#{scope.fetch("targets").length}"
puts "[INFO] stale_targets=#{scope.fetch("stale_targets").length}"
puts "[INFO] missing_sig=#{scope.fetch("missing_sig").length}"

unless scope.fetch("stale_targets").empty?
  warn "[ERROR] stale targets detected:"
  scope.fetch("stale_targets").each { |path| warn "  - #{path}" }
  exit 3
end

if !options[:allow_missing_sig] && !scope.fetch("missing_sig").empty?
  warn "[ERROR] mapped signature files are missing:"
  scope.fetch("missing_sig").each { |path| warn "  - #{path}" }
  warn "[ERROR] create the missing RBS files or rerun with --allow-missing-sig"
  exit 4
end
