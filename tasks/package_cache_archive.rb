require "fileutils"
require "json"
require "open3"
require "pathname"
require "rubygems/remote_fetcher"

class PackageCacheArchive
  attr_reader :path, :manifest

  def initialize(path:, manifest:, command_runner: nil, package_downloader: nil)
    @path = Pathname(path).expand_path
    @manifest = manifest
    @command_runner = command_runner || method(:run_command)
    @package_downloader = package_downloader || method(:download_package)
  end

  def populate
    FileUtils.mkdir_p(path)
    download_packages
    cache_git_sources unless manifest.fetch("git_sources").empty?
  end

  def prune
    expected = manifest.fetch("package_filenames") + manifest.fetch("git_sources").map { |source| git_source_directory_name(source) }
    Dir.children(path).each do |name|
      FileUtils.rm_rf(path.join(name)) unless expected.include?(name)
    end
  end

  def validate!
    expected_packages = manifest.fetch("package_filenames")
    present_packages = package_files.map { |file| File.basename(file) }
    missing_packages = expected_packages - present_packages
    missing_sources = manifest.fetch("git_sources").reject { |source| git_source_present?(source) }

    return if missing_packages.empty? && missing_sources.empty?

    failures = []
    failures << "packages: #{missing_packages.join(", ")}" unless missing_packages.empty?
    failures << "Git sources: #{missing_sources.map { |source| source.fetch("revision") }.join(", ")}" unless missing_sources.empty?
    raise "Package cache incomplete; missing #{failures.join("; ")}"
  end

  def statistics
    files = archive_files
    {
      "file_count" => files.length,
      "byte_count" => files.sum { |file| File.size(file) },
    }
  end

  private

  def archive_files
    Dir.glob(path.join("**", "*").to_s, File::FNM_DOTMATCH).select { |entry| File.file?(entry) }.sort
  end

  def package_files
    archive_files.select { |file| File.extname(file) == ".gem" }
  end

  def download_packages
    manifest.fetch("package_downloads").each do |package|
      next if path.join(package.fetch("filename")).file?

      identity = manifest.fetch("packages").find do |candidate|
        package_filename(candidate) == package.fetch("filename")
      end
      specification = Gem::Specification.new do |spec|
        spec.name = identity.fetch("name")
        spec.version = identity.fetch("version")
        spec.platform = identity.fetch("platform")
      end
      @package_downloader.call(specification, package.fetch("source_uri"), path)
    end
  end

  def cache_git_sources
    git_source_gemfiles.each do |gemfile|
      env = {
        "BUNDLE_GEMFILE" => File.expand_path(gemfile),
        "BUNDLE_CACHE_PATH" => path.to_s,
        "BUNDLE_CACHE_ALL" => "true",
        "BUNDLE_NO_PRUNE" => "true",
        "BUNDLE_FROZEN" => "true",
      }
      @command_runner.call(env, ["bundle", "cache", "--no-install"])
    end
  end

  def git_source_gemfiles
    manifest.fetch("git_sources")
      .reject { |source| git_source_present?(source) }
      .map { |source| source.fetch("gemfiles").first }
      .uniq
      .sort
  end

  def package_filename(identity)
    suffix = (identity.fetch("platform") == "ruby") ? "" : "-#{identity.fetch("platform")}"
    "#{identity.fetch("name")}-#{identity.fetch("version")}#{suffix}.gem"
  end

  def git_source_present?(source)
    source_path = path.join(git_source_directory_name(source))
    source_path.directory? && source_path.join(".bundlecache").file?
  end

  def git_source_directory_name(source)
    revision = source.fetch("revision")
    name = File.basename(source.fetch("uri"), ".git")
    "#{name}-#{revision[0, 12]}"
  end

  def download_package(specification, source_uri, destination)
    downloaded = Gem::RemoteFetcher.fetcher.download(specification, source_uri, destination.to_s)
    target = destination.join(specification.file_name)
    FileUtils.cp(downloaded, target) unless Pathname(downloaded).expand_path == target.expand_path
  end

  def run_command(env, command)
    success = system(env, *command)
    raise "Command failed: #{command.join(" ")}" unless success
  end
end
