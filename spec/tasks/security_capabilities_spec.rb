require "spec_helper"
require_relative "../../tasks/security_capabilities"

RSpec.describe SecurityCapabilities do
  describe ".for_version" do
    it "grants no features to legacy Rubies (2.5-3.0)" do
      %w[2.5 2.6 2.7 3.0].each do |v|
        expect(described_class.for_version(v)).to eq(audit: false, checksum: false, cooldown: false)
      end
    end

    it "grants audit and checksum but not cooldown on 3.1" do
      expect(described_class.for_version("3.1")).to eq(audit: true, checksum: true, cooldown: false)
    end

    it "grants all features on 3.2 and above" do
      %w[3.2 3.3 3.4 4.0].each do |v|
        expect(described_class.for_version(v)).to eq(audit: true, checksum: true, cooldown: true)
      end
    end

    it "treats an unknown future version as fully capable" do
      expect(described_class.for_version("4.1")).to eq(audit: true, checksum: true, cooldown: true)
    end
  end

  describe ".first_party_dependencies" do
    it "returns the Datadog-owned gems the gemspec depends on" do
      expect(described_class.first_party_dependencies.map(&:name)).to contain_exactly(
        "datadog-ruby_core_source",
        "libdatadog",
        "libddwaf",
      )
    end

    it "returns dependencies carrying the gemspec requirement" do
      libdatadog = described_class.first_party_dependencies.find { |d| d.name == "libdatadog" }

      expect(libdatadog.requirement.satisfied_by?(Gem::Version.new("0.0.1"))).to be false
    end

    it "omits first-party gems the gemspec no longer depends on" do
      gemspec = instance_double(Gem::Specification, dependencies: [gem_dependency("libdatadog")])
      allow(Gem::Specification).to receive(:load).with("other.gemspec").and_return(gemspec)

      expect(described_class.first_party_dependencies("other.gemspec").map(&:name)).to eq(["libdatadog"])
    end

    it "excludes third-party dependencies" do
      gemspec = instance_double(
        Gem::Specification,
        dependencies: [gem_dependency("msgpack"), gem_dependency("libddwaf")],
      )
      allow(Gem::Specification).to receive(:load).with("other.gemspec").and_return(gemspec)

      expect(described_class.first_party_dependencies("other.gemspec").map(&:name)).to eq(["libddwaf"])
    end

    def gem_dependency(name)
      instance_double(Gem::Dependency, name: name)
    end
  end

  describe ".uncooled_prelock_dependencies" do
    let(:dependencies) { [dependency("libdatadog", "~> 40.0.0.2.0")] }

    def names(lockfile, deps)
      described_class.uncooled_prelock_dependencies(lockfile, deps).map(&:name)
    end

    it "returns every dependency when the lockfile does not exist" do
      expect(names("no/such.lock", dependencies)).to eq(["libdatadog"])
    end

    it "returns the dependency when the lockfile pins a version the requirement rejects" do
      with_lockfile([["libdatadog", "40.0.0.1.0"]]) do |path|
        expect(names(path, dependencies)).to eq(["libdatadog"])
      end
    end

    it "returns the dependency when the lockfile omits the gem entirely" do
      with_lockfile([["rake", "13.3.1"]]) do |path|
        expect(names(path, dependencies)).to eq(["libdatadog"])
      end
    end

    it "returns nothing when the lockfile satisfies every requirement" do
      with_lockfile([["libdatadog", "40.0.0.2.0"]]) do |path|
        expect(names(path, dependencies)).to be_empty
      end
    end

    it "returns only the dependencies that are unsatisfied" do
      deps = [
        dependency("libdatadog", "~> 40.0.0.2.0"),
        dependency("libddwaf", "~> 1.30.0.0.0"),
        dependency("datadog-ruby_core_source", "~> 3.5"),
      ]

      with_lockfile(
        [["libdatadog", "40.0.0.1.0"], ["libddwaf", "1.30.0.0.2"], ["datadog-ruby_core_source", "3.5.5"]],
      ) do |path|
        expect(names(path, deps)).to eq(["libdatadog"])
      end
    end

    it "returns the dependency when a platform variant pins a version the requirement rejects" do
      with_lockfile([["libdatadog", "40.0.0.1.0"], ["libdatadog", "40.0.0.2.0-x86_64-linux"]]) do |path|
        expect(names(path, dependencies)).to eq(["libdatadog"])
      end
    end

    it "returns nothing when every platform variant satisfies the requirement" do
      with_lockfile([["libdatadog", "40.0.0.2.0"], ["libdatadog", "40.0.0.2.0-x86_64-linux"]]) do |path|
        expect(names(path, dependencies)).to be_empty
      end
    end

    it "returns nothing when there are no first-party dependencies" do
      with_lockfile([["rake", "13.3.1"]]) do |path|
        expect(names(path, [])).to be_empty
      end
    end

    it "returns nothing when there are no first-party dependencies and no lockfile" do
      expect(names("no/such.lock", [])).to be_empty
    end

    def dependency(name, requirement)
      Gem::Dependency.new(name, requirement)
    end

    def lockfile_body(pairs)
      specs = pairs.map { |name, version| "    #{name} (#{version})\n" }.join
      dependencies = pairs.map(&:first).uniq.sort.map { |name| "  #{name}\n" }.join

      "GEM\n  remote: https://rubygems.org/\n  specs:\n#{specs}\nPLATFORMS\n  ruby\n\n" \
        "DEPENDENCIES\n#{dependencies}\nBUNDLED WITH\n   4.0.17\n"
    end

    def with_lockfile(pairs)
      Tempfile.create(["gemfile", ".lock"]) do |file|
        file.write(lockfile_body(pairs))
        file.flush
        yield file.path
      end
    end
  end
end
