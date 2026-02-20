require "datadog/di"

RSpec.describe Datadog::DI::Configuration::Settings do
  subject(:settings) { Datadog::Core::Configuration::Settings.new }

  describe "dynamic_instrumentation" do
    context "programmatic configuration" do
      [
        [nil, "enabled", true],
        [nil, "enabled", false],
        ["internal", "untargeted_trace_points", true],
        ["internal", "untargeted_trace_points", false],
        ["internal", "propagate_all_exceptions", true],
        ["internal", "propagate_all_exceptions", false],
        ['internal', 'min_send_interval', 5],
        ['internal', 'development', true],
        ['internal', 'development', false],
        ['internal', 'max_processing_time', 0.0],
        ['internal', 'max_processing_time', 1.5],
        ['internal', 'max_processing_time', nil],
        [nil, "redacted_identifiers", ["foo"]],
        [nil, "redacted_identifiers", []],
        [nil, "redaction_excluded_identifiers", ["password"]],
        [nil, "redaction_excluded_identifiers", []],
        [nil, "redacted_type_names", ["foo*", "bar"]],
        [nil, "redacted_type_names", []],
        [nil, "max_capture_depth", 5],
        [nil, "max_capture_collection_size", 10],
        [nil, "max_capture_string_length", 20],
        [nil, "max_capture_attribute_count", 4],
      ].each do |(scope_name_, name_, value_)|
        name = name_
        scope_name = scope_name_
        value = value_.freeze

        context "when #{name} set to #{value}" do
          let(:value) { _value }

          let(:scope) do
            if scope_name
              settings.dynamic_instrumentation.public_send(scope_name)
            else
              settings.dynamic_instrumentation
            end
          end

          before do
            scope.public_send("#{name}=", value)
          end

          it "returns the value back" do
            expect(scope.public_send(name)).to eq(value)
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
        ["DD_DYNAMIC_INSTRUMENTATION_REDACTION_EXCLUDED_IDENTIFIERS", "password", "redaction_excluded_identifiers", %w[password]],
        ["DD_DYNAMIC_INSTRUMENTATION_REDACTION_EXCLUDED_IDENTIFIERS", "password,token", "redaction_excluded_identifiers", %w[password token]],
        ["DD_DYNAMIC_INSTRUMENTATION_REDACTION_EXCLUDED_IDENTIFIERS", "password, token", "redaction_excluded_identifiers", %w[password token]],
        ["DD_DYNAMIC_INSTRUMENTATION_REDACTION_EXCLUDED_IDENTIFIERS", "", "redaction_excluded_identifiers", %w[]],
        ["DD_DYNAMIC_INSTRUMENTATION_REDACTION_EXCLUDED_IDENTIFIERS", ",", "redaction_excluded_identifiers", %w[]],
        ["DD_DYNAMIC_INSTRUMENTATION_REDACTED_TYPES", "foo", "redacted_type_names", %w[foo]],
        ["DD_DYNAMIC_INSTRUMENTATION_REDACTED_TYPES", "foo,bar", "redacted_type_names", %w[foo bar]],
        ["DD_DYNAMIC_INSTRUMENTATION_REDACTED_TYPES", "foo, bar", "redacted_type_names", %w[foo bar]],
        ["DD_DYNAMIC_INSTRUMENTATION_REDACTED_TYPES", "", "redacted_type_names", %w[]],
        ["DD_DYNAMIC_INSTRUMENTATION_REDACTED_TYPES", ",", "redacted_type_names", %w[]],
        ["DD_DYNAMIC_INSTRUMENTATION_REDACTED_TYPES", ".!", "redacted_type_names", %w[.!]],
        ["DD_DYNAMIC_INSTRUMENTATION_CAPTURE_TIMEOUT", "0", "internal.max_processing_time", 0.0],
        ["DD_DYNAMIC_INSTRUMENTATION_CAPTURE_TIMEOUT", "100", "internal.max_processing_time", 0.1],
        ["DD_DYNAMIC_INSTRUMENTATION_CAPTURE_TIMEOUT", "200", "internal.max_processing_time", 0.2],
        ["DD_DYNAMIC_INSTRUMENTATION_CAPTURE_TIMEOUT", "1500", "internal.max_processing_time", 1.5],
        ["DD_DYNAMIC_INSTRUMENTATION_CAPTURE_TIMEOUT", nil, "internal.max_processing_time", 0.2],
        ["DD_DYNAMIC_INSTRUMENTATION_CAPTURE_TIMEOUT", "", "internal.max_processing_time", nil],
        ["DD_DYNAMIC_INSTRUMENTATION_CAPTURE_TIMEOUT", "-1", "internal.max_processing_time", nil],
        ["DD_DYNAMIC_INSTRUMENTATION_CAPTURE_TIMEOUT", "-999", "internal.max_processing_time", nil],
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
            # Handle nested settings like "internal.max_processing_time"
            setting_path = setting_name.split('.')
            actual_value = setting_path.reduce(settings.dynamic_instrumentation) do |obj, method|
              obj.public_send(method)
            end
            expect(actual_value).to eq setting_value
          end
        end
      end
    end
  end
end
