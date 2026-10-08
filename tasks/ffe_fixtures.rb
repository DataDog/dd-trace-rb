# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"
require "optparse"
require "tmpdir"

# Maintains the byte-for-byte snapshot used by the native evaluator specs.
module FfeFixtures
  SOURCE_REPOSITORY = "https://github.com/DataDog/ffe-system-test-data.git"
  DESTINATION = "spec/datadog/open_feature/ffe-system-test-data"
  SOURCE_METADATA = "SOURCE.md"

  module_function

  def validate_ref(ref)
    unless ref.match?(/\A[A-Za-z0-9._\/\-]+\z/) && !ref.start_with?("-") && !ref.include?("..")
      raise ArgumentError, "Invalid FFE fixture ref: #{ref}"
    end
  end

  def git(directory, environment, *arguments)
    output, error, status = Open3.capture3(environment, "git", *arguments, chdir: directory)
    raise "git #{arguments.first} failed: #{error}" unless status.success?

    output.strip
  end

  def copy_file(source, destination)
    raise "Unsupported FFE fixture entry: #{source}" if File.symlink?(source) || !File.file?(source)

    FileUtils.copy_file(source, destination)
    File.chmod(0o644, destination)
  end

  def copy_snapshot(source, snapshot)
    copy_file(File.join(source, "ufc-config.json"), File.join(snapshot, "ufc-config.json"))
    cases_directory = File.join(source, "evaluation-cases")
    if File.symlink?(cases_directory) || !File.directory?(cases_directory)
      raise "Unsupported FFE fixture directory: #{cases_directory}"
    end

    destination_cases = File.join(snapshot, "evaluation-cases")
    FileUtils.mkdir_p(destination_cases, mode: 0o755)
    Dir.children(cases_directory).sort.each do |name|
      raise "Unexpected FFE evaluation case: #{name}" unless name.end_with?(".json")

      copy_file(File.join(cases_directory, name), File.join(destination_cases, name))
    end
  end

  def validate_snapshot(snapshot)
    configuration = JSON.parse(File.read(File.join(snapshot, "ufc-config.json")))
    raise "FFE configuration must contain a flags object" unless configuration.is_a?(Hash) && configuration["flags"].is_a?(Hash)

    count = Dir[File.join(snapshot, "evaluation-cases", "*.json")].sum do |path|
      cases = JSON.parse(File.read(path))
      raise "#{path} must contain an array of test cases" unless cases.is_a?(Array)

      cases.length
    end
    raise "No FFE fixture test cases found" if count.zero?

    count
  end

  def files(directory, prefix = "")
    Dir.children(File.join(directory, prefix)).sort.flat_map do |name|
      relative = prefix.empty? ? name : File.join(prefix, name)
      path = File.join(directory, relative)
      raise "Unsupported FFE snapshot entry: #{path}" if File.symlink?(path)

      if File.directory?(path)
        files(directory, relative)
      elsif File.file?(path)
        [relative]
      else
        raise "Unsupported FFE snapshot entry: #{path}"
      end
    end.sort
  end

  def same_contents?(snapshot, destination)
    raise "Unsupported FFE snapshot directory: #{destination}" if File.symlink?(destination)
    return false unless File.directory?(destination)

    snapshot_files = files(snapshot)
    return false unless snapshot_files == files(destination).reject { |name| name == SOURCE_METADATA }

    snapshot_files.all? do |name|
      File.binread(File.join(snapshot, name)) == File.binread(File.join(destination, name))
    end
  end

  def recorded_commit(destination)
    path = File.join(destination, SOURCE_METADATA)
    raise "Unsupported FFE snapshot metadata: #{path}" if File.symlink?(destination) || File.symlink?(path)

    commits = File.read(path).scan(/^Source commit: (.*)$/).flatten
    unless commits.length == 1 && commits.first.match?(/\A[0-9a-f]{40}\z/)
      raise "#{path} must record exactly one full upstream commit SHA"
    end

    commits.first
  end

  def source_metadata(commit)
    <<~MARKDOWN
      # FFE Fixture Snapshot

      Canonical source: https://github.com/DataDog/ffe-system-test-data
      Source commit: #{commit}

      Do not edit these fixtures in dd-trace-rb. Change shared expectations upstream,
      then run `ruby tasks/ffe_fixtures.rb --ref <commit>` to refresh this snapshot.
      Verify provenance with `ruby tasks/ffe_fixtures.rb --check`.

      The weekly update workflow opens a signed draft PR when fixture contents change.
    MARKDOWN
  end

  def update(repository_root, ref: "main", check: false)
    destination = File.join(repository_root, DESTINATION)
    ref = recorded_commit(destination) if check
    validate_ref(ref)

    Dir.mktmpdir("ffe-fixtures-") do |temporary|
      source = File.join(temporary, "source")
      snapshot = File.join(temporary, "snapshot")
      FileUtils.mkdir_p([source, snapshot], mode: 0o755)
      empty_config = File.join(temporary, "gitconfig")
      File.write(empty_config, "")
      environment = {"GIT_CONFIG_NOSYSTEM" => "1", "GIT_CONFIG_GLOBAL" => empty_config}
      git(source, environment, "init", "--quiet")
      git(source, environment, "remote", "add", "origin", SOURCE_REPOSITORY)
      git(source, environment, "fetch", "--quiet", "--depth", "1", "origin", ref)
      git(source, environment, "checkout", "--quiet", "--detach", "FETCH_HEAD")
      commit = git(source, environment, "rev-parse", "HEAD")
      raise "Fetched FFE fixture commit does not match recorded SHA" if check && commit != ref

      copy_snapshot(source, snapshot)
      count = validate_snapshot(snapshot)
      changed = !same_contents?(snapshot, destination)
      if check && changed
        raise "FFE snapshot does not match SOURCE.md commit #{commit}. Refresh with: ruby tasks/ffe_fixtures.rb --ref #{commit}"
      end

      if changed
        File.write(File.join(snapshot, SOURCE_METADATA), source_metadata(commit))
        FileUtils.rm_rf(destination)
        FileUtils.mkdir_p(File.dirname(destination))
        FileUtils.cp_r(snapshot, destination)
      end

      puts "Checked #{count} FFE cases from #{commit}; fixture contents changed: #{changed}"
      if !check && ENV["GITHUB_OUTPUT"]
        File.open(ENV.fetch("GITHUB_OUTPUT"), "a") do |output|
          output.puts "source_commit=#{commit}", "fixture_count=#{count}", "changed=#{changed}"
        end
      end
    end
  end

  def main(arguments)
    ref = nil
    check = false
    parser = OptionParser.new do |options|
      options.banner = "Usage: ruby tasks/ffe_fixtures.rb [--ref REF | --check]"
      options.on("--ref REF", "Upstream branch, tag, or commit (default: main)") { |value| ref = value }
      options.on("--check", "Verify SOURCE.md provenance without changing files") { check = true }
    end
    parser.parse!(arguments)
    raise OptionParser::InvalidOption, "--ref and --check are mutually exclusive" if check && ref
    raise OptionParser::InvalidArgument, arguments.join(" ") unless arguments.empty?

    update(File.expand_path("..", __dir__), ref: ref || "main", check: check)
  end
end

FfeFixtures.main(ARGV) if $PROGRAM_NAME == __FILE__
