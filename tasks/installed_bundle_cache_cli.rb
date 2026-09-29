#!/usr/bin/env ruby

require "json"
require "optparse"
require "pathname"
require_relative "installed_bundle_cache"

options = {
  root: Pathname.pwd,
  matrix: "Matrixfile",
  strategy: "full",
  installed_path: "/usr/local/bundle",
}

parser = OptionParser.new do |opts|
  opts.on("--base-gemfile PATH") { |value| options[:base_gemfile] = value }
  opts.on("--matrix PATH") { |value| options[:matrix] = value }
  opts.on("--cache-schema VALUE") { |value| options[:cache_schema] = value }
  opts.on("--image-identity VALUE") { |value| options[:image_identity] = value }
  opts.on("--base-cache-key VALUE") { |value| options[:base_cache_key] = value }
  opts.on("--experiment-variant VALUE") { |value| options[:experiment_variant] = value }
  opts.on("--strategy VALUE") { |value| options[:strategy] = value }
  opts.on("--installed-path PATH") { |value| options[:installed_path] = value }
  opts.on("--snapshot PATH") { |value| options[:snapshot] = value }
  opts.on("--destination PATH") { |value| options[:destination] = value }
  opts.on("--groups PATH") { |value| options[:groups] = value }
  opts.on("--group VALUE") { |value| options[:group] = value }
  opts.on("--cache-path PATH") { |value| options[:cache_path] = value }
  opts.on("--base-bundle-path PATH") { |value| options[:base_bundle_path] = value }
  opts.on("--restore-status VALUE") { |value| options[:restore_status] = value }
  opts.on("--write-enabled VALUE") { |value| options[:write_enabled] = value == "true" }
  opts.on("--jobs COUNT", Integer) { |value| options[:jobs] = value }
end

command = ARGV.shift
parser.parse!(ARGV)
raise OptionParser::MissingArgument, "--base-gemfile" unless options[:base_gemfile]

matrix = GithubMatrix.new(matrix_path: options[:matrix], fallback_gemfile: options[:base_gemfile])
build_cache = lambda do |group = nil|
  InstalledBundleCache.new(
    root: options[:root],
    base_gemfile: options[:base_gemfile],
    matrix: group ? nil : matrix,
    applicable_gemfiles: group&.fetch("tasks")&.map { |task| task.fetch("gemfile") }&.uniq,
    strategy: options[:strategy],
    installed_path: options[:installed_path],
    group: group,
  )
end
load_groups = lambda do
  raise OptionParser::MissingArgument, "--groups" unless options[:groups]

  JSON.parse(Pathname(options[:groups]).read).fetch("groups")
end

case command
when "manifest"
  raise OptionParser::MissingArgument, "--cache-schema" unless options[:cache_schema]
  raise OptionParser::MissingArgument, "--image-identity" unless options[:image_identity]

  puts JSON.pretty_generate(
    build_cache.call.to_h(
      cache_schema: options[:cache_schema],
      image_identity: options[:image_identity],
      base_cache_key: options[:base_cache_key],
      experiment_variant: options[:experiment_variant],
    )
  )
when "group-manifests"
  raise OptionParser::MissingArgument, "--cache-schema" unless options[:cache_schema]
  raise OptionParser::MissingArgument, "--image-identity" unless options[:image_identity]

  manifests = load_groups.call.sort.each_with_object({}) do |(name, group), selected|
    schema = "#{options[:cache_schema]}-#{name}"
    selected[name] = build_cache.call(group).to_h(
      cache_schema: schema,
      image_identity: options[:image_identity],
      base_cache_key: options[:base_cache_key],
      experiment_variant: options[:experiment_variant],
    )
  end
  puts JSON.pretty_generate(manifests)
when "prepare-group"
  raise OptionParser::MissingArgument, "--group" unless options[:group]
  raise OptionParser::MissingArgument, "--cache-path" unless options[:cache_path]
  raise OptionParser::MissingArgument, "--base-bundle-path" unless options[:base_bundle_path]
  raise OptionParser::MissingArgument, "--snapshot" unless options[:snapshot]
  raise OptionParser::MissingArgument, "--restore-status" unless options[:restore_status]

  group = load_groups.call.fetch(options[:group])
  build_cache.call(group).prepare_group(
    base_bundle_path: options[:base_bundle_path],
    cache_path: options[:cache_path],
    base_snapshot_path: options[:snapshot],
    restore_status: options[:restore_status],
    write_enabled: options.fetch(:write_enabled, false),
    jobs: options.fetch(:jobs, 8),
  )
when "install"
  build_cache.call.install(jobs: options.fetch(:jobs, 8))
when "check"
  build_cache.call.check
when "snapshot"
  raise OptionParser::MissingArgument, "--snapshot" unless options[:snapshot]

  build_cache.call.write_snapshot(options[:snapshot])
when "extract-delta"
  raise OptionParser::MissingArgument, "--snapshot" unless options[:snapshot]
  raise OptionParser::MissingArgument, "--destination" unless options[:destination]

  build_cache.call.extract_delta(base_snapshot_path: options[:snapshot], destination: options[:destination])
else
  warn parser
  exit 1
end
