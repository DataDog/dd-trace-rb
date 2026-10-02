#!/usr/bin/env ruby

require "json"
require "optparse"
require "pathname"
require_relative "installed_bundle_cache"

options = {
  root: Pathname.pwd,
  matrix: "Matrixfile",
  installed_path: "/usr/local/bundle",
}

parser = OptionParser.new do |opts|
  opts.on("--base-gemfile PATH") { |value| options[:base_gemfile] = value }
  opts.on("--matrix PATH") { |value| options[:matrix] = value }
  opts.on("--cache-schema VALUE") { |value| options[:cache_schema] = value }
  opts.on("--image-identity VALUE") { |value| options[:image_identity] = value }
  opts.on("--base-cache-key VALUE") { |value| options[:base_cache_key] = value }
  opts.on("--installed-path PATH") { |value| options[:installed_path] = value }
  opts.on("--groups PATH") { |value| options[:groups] = value }
  opts.on("--group VALUE") { |value| options[:group] = value }
  opts.on("--base-bundle-path PATH") { |value| options[:base_bundle_path] = value }
  opts.on("--validation-path PATH") { |value| options[:validation_path] = value }
  opts.on("--jobs COUNT", Integer) { |value| options[:jobs] = value }
end

command = ARGV.shift
parser.parse!(ARGV)
raise OptionParser::MissingArgument, "--base-gemfile" unless options[:base_gemfile]

def load_groups(options)
  raise OptionParser::MissingArgument, "--groups" unless options[:groups]

  JSON.parse(Pathname(options[:groups]).read).fetch("groups")
end

def build_cache(options, group)
  InstalledBundleCache.new(
    root: options[:root],
    base_gemfile: options[:base_gemfile],
    applicable_gemfiles: group.fetch("tasks").map { |task| task.fetch("gemfile") }.uniq,
    installed_path: options[:installed_path],
    group: group.fetch("name"),
  )
end

case command
when "group-manifests"
  raise OptionParser::MissingArgument, "--cache-schema" unless options[:cache_schema]
  raise OptionParser::MissingArgument, "--image-identity" unless options[:image_identity]

  manifests = load_groups(options).sort.each_with_object({}) do |(name, group), selected|
    selected[name] = build_cache(options, group).to_h(
      cache_schema: "#{options[:cache_schema]}-#{name}",
      image_identity: options[:image_identity],
      base_cache_key: options[:base_cache_key],
    )
  end
  puts JSON.pretty_generate(manifests)
when "prepare-partitioned-groups"
  raise OptionParser::MissingArgument, "--base-bundle-path" unless options[:base_bundle_path]
  raise OptionParser::MissingArgument, "--validation-path" unless options[:validation_path]

  groups = load_groups(options)
  InstalledBundleCache.new(
    root: options[:root],
    base_gemfile: options[:base_gemfile],
    applicable_gemfiles: [],
    installed_path: options[:installed_path],
  ).prepare_partitioned_groups(
    groups: groups,
    base_bundle_path: options[:base_bundle_path],
    validation_path: options[:validation_path],
    jobs: options.fetch(:jobs, 8),
  )
when "cache-paths"
  raise OptionParser::MissingArgument, "--group" unless options[:group]

  puts build_cache(options, load_groups(options).fetch(options[:group])).cache_paths
else
  warn parser
  exit 1
end
