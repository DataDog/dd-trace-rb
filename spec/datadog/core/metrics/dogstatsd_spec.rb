require "spec_helper"
require "datadog/statsd"
require "datadog/core/metrics/dogstatsd"

RSpec.describe Datadog::Core::Metrics::Dogstatsd do
  describe ".installed_version" do
    context "when the statsd gem constant reports a version" do
      before do
        stub_const "Datadog::Statsd::VERSION", "9.9.9"
      end

      it "returns the version reported by the loaded gem" do
        expect(described_class.installed_version).to eq(Gem::Version.new("9.9.9"))
      end
    end

    context "when the statsd gem constant does not report a version" do
      before do
        stub_const "Datadog::Statsd::VERSION", nil
        allow(Gem.loaded_specs).to receive(:[])
          .with("dogstatsd-ruby")
          .and_return(loaded_spec)
      end

      context "when the gem is registered in loaded specs" do
        let(:loaded_spec) { instance_double(Gem::Specification, version: Gem::Version.new("5.7.1")) }

        it "returns the version of the registered gem" do
          expect(described_class.installed_version).to eq(Gem::Version.new("5.7.1"))
        end
      end

      context "when the gem is not registered in loaded specs" do
        let(:loaded_spec) { nil }

        it "returns nil" do
          expect(described_class.installed_version).to be nil
        end
      end
    end
  end

  describe ".supported?" do
    [
      ["3.2.9", false],
      ["3.3.0", true],
      ["4.9.0", true],
      ["5.0.0", false],
      ["5.0.5", false],
      ["5.1.0", false],
      ["5.2.9", false],
      ["5.3.0", true],
      ["6.0.0", true],
    ].each do |version_string, expected_supported|
      context "with version #{version_string}" do
        let(:version) { Gem::Version.new(version_string) }

        it "returns #{expected_supported}" do
          expect(described_class.supported?(version)).to be(expected_supported)
        end
      end
    end

    context "without a version" do
      it "returns false" do
        expect(described_class.supported?(nil)).to be false
      end
    end
  end

  describe ".single_thread_supported?" do
    [
      ["5.1.9", false],
      ["5.2.0", true],
      ["6.0.0", true],
    ].each do |version_string, expected_supported|
      context "with version #{version_string}" do
        let(:version) { Gem::Version.new(version_string) }

        it "returns #{expected_supported}" do
          expect(described_class.single_thread_supported?(version)).to be(expected_supported)
        end
      end
    end
  end

  describe ".default_hostname" do
    context "when the agent host environment variable is" do
      context "set" do
        let(:value) { "my-hostname" }

        around do |example|
          ClimateControl.modify(Datadog::Core::Configuration::Ext::Agent::ENV_DEFAULT_HOST => value) do
            example.run
          end
        end

        it "returns the configured host" do
          expect(described_class.default_hostname).to eq(value)
        end
      end

      context "not set" do
        with_env Datadog::Core::Configuration::Ext::Agent::ENV_DEFAULT_HOST => nil

        it "returns the default host" do
          expect(described_class.default_hostname).to eq(Datadog::Core::Metrics::Ext::DEFAULT_HOST)
        end
      end
    end
  end

  describe ".default_port" do
    context "when the metric agent port environment variable is" do
      context "set" do
        let(:value) { "1234" }

        around do |example|
          ClimateControl.modify(Datadog::Core::Configuration::Ext::Metrics::ENV_DEFAULT_PORT => value) do
            example.run
          end
        end

        it "returns the configured port" do
          expect(described_class.default_port).to eq(value.to_i)
        end
      end

      context "not set" do
        with_env Datadog::Core::Configuration::Ext::Metrics::ENV_DEFAULT_PORT => nil

        it "returns the default port" do
          expect(described_class.default_port).to eq(Datadog::Core::Metrics::Ext::DEFAULT_PORT)
        end
      end
    end
  end
end
