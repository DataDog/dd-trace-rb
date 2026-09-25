require "bundler"
require "digest"
require "json"
require "pathname"
require "set"
require_relative "github_matrix"

class PackageCacheManifest
  SCHEMA_VERSION = 1

  attr_reader :root, :base_gemfile, :appraisal_gemfiles, :platform, :runtime_identifier

  def initialize(
    root: Pathname.pwd,
    base_gemfile: AppraisalConversion.parent_gemfile,
    matrix: nil,
    appraisal_gemfiles: nil,
    platform: Gem::Platform.local.to_s,
    runtime_identifier: AppraisalConversion.runtime_identifier
  )
    raise ArgumentError, "Provide matrix or appraisal_gemfiles, not both" if matrix && appraisal_gemfiles

    @root = Pathname(root).expand_path
    @base_gemfile = absolute_path(base_gemfile)
    selected_gemfiles = appraisal_gemfiles || (matrix || GithubMatrix.new).appraisal_gemfiles
    @appraisal_gemfiles = selected_gemfiles.map { |path| absolute_path(path) }.sort
    @platform = Gem::Platform.new(platform)
    @runtime_identifier = runtime_identifier
  end

  def lockfiles
    ([lockfile_for(base_gemfile)] + appraisal_gemfiles.map { |path| lockfile_for(path) }).uniq.sort
  end

  def lockfile_digest
    digest = Digest::SHA256.new

    lockfiles.each do |path|
      digest << relative_path(path) << "\0" << File.binread(path) << "\0"
    end

    digest.hexdigest
  end

  def packages
    base = package_identities(lockfile_for(base_gemfile)).to_set

    appraisal_gemfiles.flat_map { |path| package_identities(lockfile_for(path)) }
      .uniq
      .reject { |identity| base.include?(identity) }
      .sort_by { |identity| [identity.fetch(:name), identity.fetch(:version), identity.fetch(:platform)] }
  end

  def git_sources
    sources = appraisal_gemfiles.flat_map do |gemfile|
      parser(lockfile_for(gemfile)).sources.each_with_object([]) do |source, selected|
        next unless source.respond_to?(:uri) && source.respond_to?(:revision)

        selected << {
          uri: source.uri.to_s,
          revision: source.revision.to_s,
          gemfile: relative_path(gemfile),
        }
      end
    end

    sources.group_by { |source| [source.fetch(:uri), source.fetch(:revision)] }.map do |(uri, revision), matches|
      {
        uri: uri,
        revision: revision,
        gemfiles: matches.map { |source| source.fetch(:gemfile) }.uniq.sort,
      }
    end.sort_by { |source| [source.fetch(:uri), source.fetch(:revision)] }
  end

  def package_filenames
    packages.map { |identity| package_filename(identity) }
  end

  def package_downloads
    packages.map do |identity|
      {
        filename: package_filename(identity),
        source_uri: package_sources.fetch(package_identity(identity)),
      }
    end
  end

  def to_h
    {
      schema_version: SCHEMA_VERSION,
      runtime_identifier: runtime_identifier,
      platform: platform.to_s,
      base_gemfile: relative_path(base_gemfile),
      appraisal_gemfiles: appraisal_gemfiles.map { |path| relative_path(path) },
      lockfile_digest: lockfile_digest,
      packages: packages,
      package_filenames: package_filenames,
      package_downloads: package_downloads,
      git_sources: git_sources,
    }
  end

  def to_json(*args)
    JSON.generate(to_h, *args)
  end

  private

  def package_identities(lockfile)
    rubygems_specs(parser(lockfile)).map { |spec| package_identity_for_spec(spec) }
  end

  def package_identity_for_spec(spec)
    {
      name: spec.name,
      version: spec.version.to_s,
      platform: spec.platform.to_s,
    }
  end

  def package_identity(identity)
    [identity.fetch(:name), identity.fetch(:version), identity.fetch(:platform)]
  end

  def package_sources
    @package_sources ||= lockfiles.each_with_object({}) do |lockfile, sources|
      rubygems_specs(parser(lockfile)).each do |spec|
        source = spec.source.remotes.first
        sources[package_identity(package_identity_for_spec(spec))] ||= source.to_s
      end
    end
  end

  def rubygems_specs(lockfile_parser)
    specs = lockfile_parser.specs.select { |spec| spec.source.is_a?(Bundler::Source::Rubygems) }

    specs.group_by { |spec| [spec.name, spec.version.to_s] }.each_with_object([]) do |(_identity, variants), selected|
      matching = variants.select { |spec| platform_match?(spec.platform) }
      native = matching.reject { |spec| spec.platform.to_s == "ruby" }
      selected.concat(native.empty? ? matching : native)
    end
  end

  def platform_match?(spec_platform)
    spec_platform.to_s == "ruby" || platform === Gem::Platform.new(spec_platform.to_s)
  end

  def package_filename(identity)
    suffix = (identity.fetch(:platform) == "ruby") ? "" : "-#{identity.fetch(:platform)}"
    "#{identity.fetch(:name)}-#{identity.fetch(:version)}#{suffix}.gem"
  end

  def parser(lockfile)
    @parsers ||= {}
    @parsers[lockfile] ||= Bundler::LockfileParser.new(File.read(lockfile))
  end

  def lockfile_for(gemfile)
    path = Pathname("#{gemfile}.lock")
    raise "Lockfile not found: #{relative_path(path)}" unless path.file?

    path
  end

  def absolute_path(path)
    path = Pathname(path)
    path.absolute? ? path : root.join(path)
  end

  def relative_path(path)
    Pathname(path).relative_path_from(root).to_s
  rescue ArgumentError
    Pathname(path).to_s
  end
end
