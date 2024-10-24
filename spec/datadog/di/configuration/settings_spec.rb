require "datadog/di"

RSpec.describe Datadog::DI::Configuration::Settings do
  subject(:settings) { Datadog::Core::Configuration::Settings.new }

  describe "dynamic_instrumentation" do
    context "programmatic configuration" do
      [
        ["enabled", true],
        ["enabled", false],
        ["untargeted_trace_points", true],
        ["untargeted_trace_points", false],
        ["propagate_all_exceptions", true],
        ["propagate_all_exceptions", false],
        ["redacted_identifiers", ["foo"]],
        ["redacted_identifiers", []],
        ["redacted_type_names", ["foo*", "bar"]],
        ["redacted_type_names", []],
        ["max_capture_depth", 5],
        ["max_capture_collection_size", 10],
        ["max_capture_string_length", 20],
        ["max_capture_attribute_count", 4],
      ].each do |(name_, value_)|
        name = name_
        value = value_.freeze

        context "when #{name} set to #{value}" do
          let(:value) { _value }

          before do
            settings.dynamic_instrumentation.public_send("#{name}=", value)
          end

          it "returns the value back" do
            expect(settings.dynamic_instrumentation.public_send(name)).to eq(value)
          end
        end
      end
    end

    context "environment variable configuration" do
      [
        ["DD_DYNAMIC_INSTRUMENTATION_ENABLED", "true", "enabled", true],
        ["DD_DYNAMIC_INSTRUMENTATION_ENABLED", "false", "enabled", false],
        ["DD_DYNAMIC_INSTRUMENTATION_ENABLED", nil, "enabled", false],
        ["DD_DYNAMIC_INSTRUMENTATION_REDACTED_IDENTIFIERS", "foo", "redacted_identifiers", %w[foo]],
        ["DD_DYNAMIC_INSTRUMENTATION_REDACTED_IDENTIFIERS", "foo,bar", "redacted_identifiers", %w[foo bar]],
        ["DD_DYNAMIC_INSTRUMENTATION_REDACTED_IDENTIFIERS", "foo, bar", "redacted_identifiers", %w[foo bar]],
        ["DD_DYNAMIC_INSTRUMENTATION_REDACTED_IDENTIFIERS", "", "redacted_identifiers", %w[]],
        ["DD_DYNAMIC_INSTRUMENTATION_REDACTED_IDENTIFIERS", ",", "redacted_identifiers", %w[]],
        ["DD_DYNAMIC_INSTRUMENTATION_REDACTED_IDENTIFIERS", "~?", "redacted_identifiers", %w[~?]],
        ["DD_DYNAMIC_INSTRUMENTATION_REDACTED_TYPES", "foo", "redacted_type_names", %w[foo]],
        ["DD_DYNAMIC_INSTRUMENTATION_REDACTED_TYPES", "foo,bar", "redacted_type_names", %w[foo bar]],
        ["DD_DYNAMIC_INSTRUMENTATION_REDACTED_TYPES", "foo, bar", "redacted_type_names", %w[foo bar]],
        ["DD_DYNAMIC_INSTRUMENTATION_REDACTED_TYPES", "", "redacted_type_names", %w[]],
        ["DD_DYNAMIC_INSTRUMENTATION_REDACTED_TYPES", ",", "redacted_type_names", %w[]],
        ["DD_DYNAMIC_INSTRUMENTATION_REDACTED_TYPES", ".!", "redacted_type_names", %w[.!]],
      ].each do |(env_var_name_, env_var_value_, setting_name_, setting_value_)|
        env_var_name = env_var_name_
        env_var_value = env_var_value_
        setting_name = setting_name_
        setting_value = setting_value_

        context "when #{env_var_name}=#{env_var_value}" do
          around do |example|
            ClimateControl.modify(env_var_name => env_var_value) do
              example.run
            end
          end

          it "sets dynamic_instrumentation.#{setting_name}=#{setting_value}" do
            expect(settings.dynamic_instrumentation.public_send(setting_name)).to eq setting_value
          end
        end
      end
    end
  end
end
