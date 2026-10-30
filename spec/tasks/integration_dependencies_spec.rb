require "spec_helper"
require "open3"
require "tmpdir"
require "fileutils"
require_relative "../../integration/images/include/datadog/demo_env"

RSpec.describe "Integration native dependencies" do
  let(:version) { "46.0.0.1.0" }
  let(:requirement) { ">= 46.0.0.1.0" }
  let(:ruby) { RUBY_VERSION.split(".").take(2).join(".") }
  let(:demo_env) { File.expand_path("../../integration/images/include/datadog/demo_env", __dir__) }

  around do |example|
    load_path = $LOAD_PATH.dup
    $LOAD_PATH.unshift(File.dirname(File.dirname(demo_env)))
    Dir.mktmpdir("integration-dependencies") do |dir|
      @dir = dir
      example.run
    end
  ensure
    $LOAD_PATH.replace(load_path)
  end

  before do
    FileUtils.mkdir_p("#{@dir}/gemfiles")
    write_lockfile("#{@dir}/gemfiles/ruby-#{ruby}.gemfile.lock", version)
    write_lockfile("#{@dir}/Gemfile.lock", "46.0.0.1.1")
    write_gemspec("libdatadog", "46.0.0.1.0")
    write_gemspec("libdatadog", "46.0.0.1.1")
    write_gemspec("framework", "1.0.0", requirement)

    File.write("#{@dir}/app.gemfile", <<~GEMFILE)
      require #{demo_env.inspect}
      path #{@dir.inspect} do
        gem 'framework', '~> 1.0'
        gem 'libdatadog', Datadog::DemoEnv.locked_libdatadog_version
      end
    GEMFILE
  end

  def write_lockfile(path, version)
    File.write(path, "GEM\n  specs:\n    libdatadog (#{version})\n\nPLATFORMS\n  ruby\n\nDEPENDENCIES\n  libdatadog\n")
  end

  def write_gemspec(name, version, requirement = nil)
    path = "#{@dir}/#{name}-#{version}"
    FileUtils.mkdir_p(path)
    File.write("#{path}/#{name}.gemspec", <<~GEMSPEC)
      Gem::Specification.new do |spec|
        spec.name = #{name.inspect}
        spec.version = #{version.inspect}
        spec.summary = 'Integration dependency fixture'
        spec.authors = ['Test']
        #{"spec.add_dependency 'libdatadog', #{requirement.inspect}" if requirement}
      end
    GEMSPEC
  end

  def resolve
    bundle = Gem.bin_path("bundler", "bundle")
    Bundler.with_unbundled_env do
      Open3.capture2e(
        {"BUNDLE_GEMFILE" => "#{@dir}/app.gemfile", "DD_DEMO_ENV_GEM_LOCAL_DATADOG" => @dir},
        Gem.ruby, bundle, "lock", "--local",
      )
    end
  end

  it "selects the per-Ruby repository lock over a newer available version and the root lock" do
    output, status = resolve

    expect(status).to be_success, output
    lock = Bundler::LockfileParser.new(File.read("#{@dir}/app.gemfile.lock"))
    expect(lock.specs.find { |spec| spec.name == "libdatadog" }.version.to_s).to eq("46.0.0.1.0")
  end

  context "when the repository locks the newer version" do
    let(:version) { "46.0.0.1.1" }
    let(:requirement) { "= 46.0.0.1.1" }

    it "resolves compatible application constraints" do
      output, status = resolve

      expect(status).to be_success, output
      lock = Bundler::LockfileParser.new(File.read("#{@dir}/app.gemfile.lock"))
      expect(lock.specs.find { |spec| spec.name == "libdatadog" }.version.to_s).to eq("46.0.0.1.1")
    end
  end

  context "when the application requires a newer version" do
    let(:requirement) { ">= 46.0.0.1.1" }

    it "rejects the conflict rather than overriding either constraint" do
      output, status = resolve

      expect(status).not_to be_success
      expect(output).to include("libdatadog", "46.0.0.1.0", "46.0.0.1.1")
    end
  end

  it "fails when the matching repository lockfile is missing" do
    File.delete("#{@dir}/gemfiles/ruby-#{ruby}.gemfile.lock")
    output, status = resolve

    expect(status).not_to be_success
    expect(output).to include("ruby-#{ruby}.gemfile.lock")
  end

  it "pins every local integration app to the repository version" do
    ClimateControl.modify("DD_DEMO_ENV_GEM_LOCAL_DATADOG" => @dir) do
      Dir[File.expand_path("../../integration/apps/*/Gemfile", __dir__)].each do |gemfile|
        dsl = Bundler::Dsl.new
        dsl.eval_gemfile(gemfile)
        dependency = dsl.dependencies.find { |dep| dep.name == "libdatadog" }

        expect(dependency).not_to be_nil, gemfile
        expect(dependency.requirement.to_s).to eq("= 46.0.0.1.0"), gemfile
      end
    end
  end
end
