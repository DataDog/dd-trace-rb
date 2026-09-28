require "json"
require "optparse"
require_relative "github_matrix"
require_relative "package_cache_archive"
require_relative "package_cache_manifest"

class PackageCacheCLI
  DEFAULT_CACHE_SCHEMA = "bundle-packages-v1"

  def self.run(arguments)
    new(arguments).run
  end

  def initialize(arguments)
    @arguments = arguments.dup
    @options = {}
  end

  def run
    command = @arguments.shift

    case command
    when "manifest"
      write_manifest
    when "populate"
      update_archive(:populate)
    when "prune"
      update_archive(:prune)
    when "validate"
      update_archive(:validate!)
    when "statistics"
      puts JSON.generate(archive.statistics)
    else
      raise ArgumentError, "Unknown package cache command: #{command}"
    end
  end

  private

  def write_manifest
    parse_manifest_options
    matrix = GithubMatrix.new(
      matrix_path: @options.fetch(:matrix),
      ruby_version: @options.fetch(:ruby_version),
      gemfile_resolver: gemfile_resolver,
    )
    manifest = PackageCacheManifest.new(
      root: @options.fetch(:root, Dir.pwd),
      base_gemfile: @options.fetch(:base_gemfile),
      matrix: matrix,
      platform: @options.fetch(:platform, Gem::Platform.local.to_s),
      runtime_identifier: @options.fetch(:runtime_identifier),
    )
    content = manifest.to_h
    prefix = [
      @options.fetch(:cache_schema, DEFAULT_CACHE_SCHEMA),
      content.fetch(:runtime_identifier),
      content.fetch(:platform),
      "bundler-#{Bundler::VERSION}",
    ].join("-") + "-"
    content[:cache_key_prefix] = prefix
    content[:cache_key] = "#{prefix}#{content.fetch(:lockfile_digest)}"
    File.write(@options.fetch(:output), JSON.pretty_generate(content))
  end

  def parse_manifest_options
    OptionParser.new do |parser|
      parser.on("--root PATH") { |value| @options[:root] = value }
      parser.on("--cache-schema SCHEMA") { |value| @options[:cache_schema] = value }
      parser.on("--base-gemfile PATH") { |value| @options[:base_gemfile] = value }
      parser.on("--matrix PATH") { |value| @options[:matrix] = value }
      parser.on("--ruby-version VERSION") { |value| @options[:ruby_version] = value }
      parser.on("--runtime-identifier IDENTIFIER") { |value| @options[:runtime_identifier] = value }
      parser.on("--platform PLATFORM") { |value| @options[:platform] = value }
      parser.on("--appraisal-pattern PATTERN") { |value| @options[:appraisal_pattern] = value }
      parser.on("--output PATH") { |value| @options[:output] = value }
    end.parse!(@arguments)
  end

  def gemfile_resolver
    pattern = @options[:appraisal_pattern]
    return AppraisalConversion.method(:to_bundle_gemfile) unless pattern

    lambda { |group| format(pattern, group: group) }
  end

  def update_archive(operation)
    parse_archive_options
    archive.public_send(operation)
  end

  def archive
    parse_archive_options
    manifest = JSON.parse(File.read(@options.fetch(:manifest)))
    PackageCacheArchive.new(path: @options.fetch(:path), manifest: manifest)
  end

  def parse_archive_options
    return if @archive_options_parsed

    OptionParser.new do |parser|
      parser.on("--manifest PATH") { |value| @options[:manifest] = value }
      parser.on("--path PATH") { |value| @options[:path] = value }
    end.parse!(@arguments)
    @archive_options_parsed = true
  end
end

PackageCacheCLI.run(ARGV) if $PROGRAM_NAME == __FILE__
