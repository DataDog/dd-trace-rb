require "spec_helper"

require "datadog/core/telemetry/event/app_client_configuration_change"

RSpec.describe Datadog::Core::Telemetry::Event::AppClientConfigurationChange do
  let(:event) { described_class.new }

  let(:event) { described_class.new(changes, origin) }
  let(:changes) { {name => value} }
  let(:origin) { double("origin") }
  let(:name) { "key" }
  let(:value) { "value" }

  describe ".payload" do
    subject(:payload) { event.payload }

    it "has a list of client configurations" do
      is_expected.to eq(
        configuration: [{
          name: name,
          value: value,
          origin: origin,
          seq_id: 6,
        }]
      )
    end

    context "with an array value" do
      let(:value) { ["X-Test-Header:test_header_rc", "Content-Length:"] }

      it "serializes the value as a scalar" do
        expect(payload[:configuration]).to contain_exactly(
          {
            name: name,
            value: "X-Test-Header:test_header_rc,Content-Length:",
            origin: origin,
            seq_id: 6,
          }
        )
      end
    end

    context "with a hash value" do
      let(:value) { {service: "web-*", env: "prod"} }

      it "serializes the value as a scalar" do
        expect(payload[:configuration]).to contain_exactly(
          {
            name: name,
            value: "service:web-*,env:prod",
            origin: origin,
            seq_id: 6,
          }
        )
      end
    end

    context "with a floating-point value" do
      let(:value) { 0.2 }

      it "preserves the numeric value" do
        expect(payload[:configuration]).to contain_exactly(
          {
            name: name,
            value: 0.2,
            origin: origin,
            seq_id: 6,
          }
        )
      end
    end

    [Float::NAN, Float::INFINITY, -Float::INFINITY].each do |non_finite_value|
      context "with #{non_finite_value}" do
        let(:value) { non_finite_value }

        it "serializes the value as valid JSON" do
          expect(payload[:configuration].first[:value]).to eq(non_finite_value.to_s)
          expect { JSON.parse(JSON.dump(payload)) }.not_to raise_error
        end
      end
    end

    context "with env_var state configuration" do
      before do
        Datadog.configure do |c|
          c.appsec.sca_enabled = false
        end
      end

      after do
        Datadog.configuration.reset!
      end

      it "includes sca enablement configuration" do
        is_expected.to eq(
          configuration:
          [
            {name: name, value: value, origin: origin, seq_id: 6},
            {name: "appsec.sca_enabled", value: false, origin: "code", seq_id: 5},
          ]
        )
      end
    end
  end

  it "all events to be the same" do
    events = [
      described_class.new({"key" => "value"}, "origin"),
      described_class.new({"key" => "value"}, "origin"),
    ]

    expect(events.uniq).to have(1).item
  end

  it "all events to be different" do
    events = [
      described_class.new({"key" => "value"}, "origin"),
      described_class.new({"key" => "value"}, "origin2"),
      described_class.new({"key" => "value2"}, "origin"),
      described_class.new({"key2" => "value"}, "origin"),
      described_class.new({}, "origin"),
    ]

    expect(events.uniq).to eq(events)
  end
end
