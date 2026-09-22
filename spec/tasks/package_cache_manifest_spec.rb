require "spec_helper"
require "fileutils"
require "tmpdir"
require_relative "../../tasks/package_cache_manifest"

RSpec.describe PackageCacheManifest do
  subject(:manifest) do
    described_class.new(
      root: temporary_directory,
      base_gemfile: "gemfiles/ruby-4.0.gemfile",
      matrix: matrix,
      platform: "x86_64-linux",
    )
  end

  let(:matrix) { instance_double(GithubMatrix, appraisal_gemfiles: appraisal_gemfiles) }
  let(:appraisal_gemfiles) do
    [
      File.join(temporary_directory, "gemfiles/ruby_4.0_second.gemfile"),
      File.join(temporary_directory, "gemfiles/ruby_4.0_first.gemfile"),
    ]
  end

  around do |example|
    Dir.mktmpdir do |directory|
      @temporary_directory = directory
      FileUtils.mkdir_p(File.join(directory, "gemfiles"))
      example.run
    end
  end

  let(:temporary_directory) { @temporary_directory }

  before do
    write_bundle("gemfiles/ruby-4.0.gemfile", base_lockfile)
    write_bundle("gemfiles/ruby_4.0_first.gemfile", first_lockfile)
    write_bundle("gemfiles/ruby_4.0_second.gemfile", second_lockfile)
  end

  def write_bundle(relative_path, lockfile)
    path = File.join(temporary_directory, relative_path)
    File.write(path, "source \"https://rubygems.org\"\n")
    File.write("#{path}.lock", lockfile)
  end

  def lockfile(specs:, platforms: ["ruby", "x86_64-linux"], git: nil)
    git_section = if git
      <<~GIT_SECTION
        GIT
          remote: #{git.fetch(:uri)}
          revision: #{git.fetch(:revision)}
          specs:
            rails (4.2.11.3)

      GIT_SECTION
    else
      ""
    end

    <<~LOCK
      #{git_section}GEM
        remote: https://rubygems.org/
        specs:
      #{specs.map { |spec| "    #{spec}" }.join("\n")}

      PLATFORMS
      #{platforms.map { |platform| "  #{platform}" }.join("\n")}

      DEPENDENCIES
        datadog

      BUNDLED WITH
         4.0.19
    LOCK
  end

  let(:base_lockfile) do
    lockfile(specs: ["logger (1.7.0)"])
  end

  let(:first_lockfile) do
    lockfile(
      specs: [
        "excon (1.7.1)",
        "logger (1.7.0)",
        "native (1.0.0)",
        "native (1.0.0-x86_64-linux)",
        "native (1.0.0-arm64-darwin)",
      ],
      git: {
        uri: "https://github.com/DataDog/rails",
        revision: "592dfae8747db3bb28c3292a9730817f0fa76885",
      },
    )
  end

  let(:second_lockfile) do
    lockfile(specs: ["excon (1.7.1)", "logger (1.7.0)", "rake (13.2.1)"])
  end

  it "uses applicable lockfiles in deterministic order" do
    expect(manifest.lockfiles.map { |path| path.relative_path_from(Pathname(temporary_directory)).to_s }).to eq(
      [
        "gemfiles/ruby-4.0.gemfile.lock",
        "gemfiles/ruby_4.0_first.gemfile.lock",
        "gemfiles/ruby_4.0_second.gemfile.lock",
      ]
    )
  end

  it "subtracts base packages and selects packages for the runtime platform" do
    expect(manifest.packages).to eq(
      [
        {name: "excon", version: "1.7.1", platform: "ruby"},
        {name: "native", version: "1.0.0", platform: "x86_64-linux"},
        {name: "rake", version: "13.2.1", platform: "ruby"},
      ]
    )
    expect(manifest.package_filenames).to eq(
      [
        "excon-1.7.1.gem",
        "native-1.0.0-x86_64-linux.gem",
        "rake-13.2.1.gem",
      ]
    )
    expect(manifest.package_downloads).to eq(
      [
        {filename: "excon-1.7.1.gem", source_uri: "https://rubygems.org/"},
        {filename: "native-1.0.0-x86_64-linux.gem", source_uri: "https://rubygems.org/"},
        {filename: "rake-13.2.1.gem", source_uri: "https://rubygems.org/"},
      ]
    )
  end

  it "retains Git source URL and revision" do
    expect(manifest.git_sources).to eq(
      [
        {
          uri: "https://github.com/DataDog/rails",
          revision: "592dfae8747db3bb28c3292a9730817f0fa76885",
          gemfiles: ["gemfiles/ruby_4.0_first.gemfile"],
        },
      ]
    )
  end

  it "changes the digest when an applicable lockfile changes" do
    original_digest = manifest.lockfile_digest
    File.write("#{appraisal_gemfiles.first}.lock", "#{second_lockfile}\n")

    expect(manifest.lockfile_digest).not_to eq(original_digest)
  end

  it "rejects missing lockfiles" do
    File.delete("#{appraisal_gemfiles.first}.lock")

    expect { manifest.lockfiles }.to raise_error(
      RuntimeError,
      "Lockfile not found: gemfiles/ruby_4.0_second.gemfile.lock",
    )
  end
end
