require "spec_helper"

require "datadog/core/telemetry/event/configuration_value"

RSpec.describe Datadog::Core::Telemetry::Event::ConfigurationValue do
  describe ".convert" do
    subject(:converted_value) { described_class.convert(value) }

    {
      nil => nil,
      true => true,
      false => false,
      1 => 1,
      "value" => "value",
      0.5 => 0.5,
      ["one", "two"] => "one,two",
      {one: 1, two: 2} => "one:1,two:2",
      Datadog::Core => "Datadog::Core",
    }.each do |input, expected|
      context "with #{input.inspect}" do
        let(:value) { input }

        it { is_expected.to eq(expected) }
      end
    end

    context "with a value that implements #to_s" do
      let(:value) do
        Class.new do
          def to_s
            "custom"
          end
        end.new
      end

      it { is_expected.to eq("custom") }
    end

    context "with a value that inherits Kernel#to_s" do
      before { stub_const("TelemetryConfigurationValue", Class.new) }

      let(:value) { TelemetryConfigurationValue.new }

      it { is_expected.to eq("TelemetryConfigurationValue") }
    end

    context "with a value whose #to_s raises NameError" do
      let(:value) do
        Class.new do
          def to_s
            raise NameError, "sentinel"
          end
        end.new
      end

      it "propagates the error" do
        expect { converted_value }.to raise_error(NameError, "sentinel")
      end
    end

    {
      Float::NAN => "NaN",
      Float::INFINITY => "Infinity",
      -Float::INFINITY => "-Infinity",
    }.each do |input, expected|
      context "with #{input}" do
        let(:value) { input }

        it { is_expected.to eq(expected) }
      end
    end
  end
end
