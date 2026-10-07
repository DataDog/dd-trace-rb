#!/usr/bin/env ruby
# frozen_string_literal: true

# Writes `supported_versions.json` for the one-pipeline `generate-supported-versions` job, which uploads it to S3.

require "bundler/setup"
require "json"
require "set"

ROOT = File.expand_path("..", __dir__)
$LOAD_PATH.unshift(File.join(ROOT, "lib"))
require "datadog"

class SupportedVersionsGenerator
  OUTPUT_PATH = File.join(ROOT, "supported_versions.json")
  MATRIX = eval(File.read(File.join(ROOT, "Matrixfile"))).freeze # rubocop:disable Security/Eval

  # Not locked in gemfiles: the tested Ruby version is the tested gem version.
  RUBY_BUNDLED_GEMS = ["net-http"].freeze

  # Specs that don't run under a Matrixfile task named after the integration directory.
  MATRIX_TASK_OVERRIDES = {"active_job" => "railsactivejob"}.freeze

  def initialize
    @locked_versions = {}
  end

  def generate
    entries = Datadog::Tracing::Contrib::REGISTRY.map { |entry| build_entry(entry) }.compact
    entries.sort_by! { |entry| [entry[:integrationName], entry[:dependencyName]] }
    File.write(OUTPUT_PATH, "#{JSON.pretty_generate(entries)}\n")
  end

  private

  def build_entry(entry)
    integration = entry.klass
    dependency_name = dependency_name(entry)
    tested = tested_versions(integration, dependency_name)
    return if tested.empty?

    {
      dependencyName: dependency_name,
      integrationName: integration.name.to_s,
      autoInstrumented: integration.auto_instrument?,
      versions: build_versions(tested, supported_range(integration.class, dependency_name)),
    }
  end

  # Aliases share the aliased integration instance, and are named after their own gem (e.g. `kicks` for `sneakers`).
  def dependency_name(entry)
    integration = entry.klass
    return entry.name.to_s if entry.name != integration.name

    integration.class.respond_to?(:gem_name) ? integration.class.gem_name : integration.name.to_s
  end

  # Matrixfile tasks follow the integration directory, not the registered name (e.g. `mongodb` for `mongo`).
  def matrix_task(integration)
    directory = File.basename(File.dirname(Object.const_source_location(integration.class.name).first))
    MATRIX_TASK_OVERRIDES.fetch(directory, directory)
  end

  def tested_versions(integration, dependency_name)
    tested = {}
    MATRIX.fetch(matrix_task(integration), {}).each do |group, rubies|
      tested_rubies(rubies).each do |ruby_version|
        if RUBY_BUNDLED_GEMS.include?(dependency_name)
          tested[ruby_version] ||= Set.new
        elsif (version = locked_versions(lockfile_path(ruby_version, group))[dependency_name])
          (tested[ruby_version] ||= Set.new) << version
        end
      end
    end
    tested
  end

  def tested_rubies(rubies)
    rubies.scan(/✅ (\S+)/).flatten
  end

  def lockfile_path(ruby_version, group)
    gemfile = group.empty? ? "ruby-#{ruby_version}.gemfile" : "ruby_#{ruby_version}_#{group}.gemfile".tr("-", "_")
    File.join(ROOT, "gemfiles", "#{gemfile}.lock")
  end

  def locked_versions(path)
    @locked_versions[path] ||=
      if File.exist?(path)
        Bundler::LockfileParser.new(File.read(path)).specs.each_with_object({}) do |spec, versions|
          versions[spec.name] = spec.version.to_s
        end
      else
        {}
      end
  end

  def supported_range(integration_class, dependency_name)
    return "*" if RUBY_BUNDLED_GEMS.include?(dependency_name)
    return unless integration_class.const_defined?(:MINIMUM_VERSION, false)

    range = ">=#{integration_class::MINIMUM_VERSION}"
    range += ",<#{integration_class::MAXIMUM_VERSION}" if integration_class.const_defined?(:MAXIMUM_VERSION, false)
    range
  end

  # Ruby versions that tested the same gem versions share one entry.
  def build_versions(tested, supported_range)
    versions = tested.group_by { |_, gem_versions| sort_versions(gem_versions) }.map do |gem_versions, runtimes|
      version = {testedRuntimes: {ruby: sort_versions(runtimes.map(&:first))}}
      version[:supportedRange] = supported_range if supported_range
      version[:tested] = gem_versions
      version
    end
    versions.sort_by { |version| Gem::Version.new(version[:testedRuntimes][:ruby].first) }
  end

  def sort_versions(versions)
    versions.sort_by { |version| Gem::Version.new(version) }
  end
end

SupportedVersionsGenerator.new.generate
