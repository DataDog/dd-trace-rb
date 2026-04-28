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
        [nil, "DD_DYNAMIC_INSTRUMENTATION_ENABLED", "true", "enabled", true],
        [nil, "DD_DYNAMIC_INSTRUMENTATION_ENABLED", "false", "enabled", false],
        [nil, "DD_DYNAMIC_INSTRUMENTATION_ENABLED", nil, "enabled", false],
        [nil, "DD_DYNAMIC_INSTRUMENTATION_REDACTED_IDENTIFIERS", "foo", "redacted_identifiers", %w[foo]],
        [nil, "DD_DYNAMIC_INSTRUMENTATION_REDACTED_IDENTIFIERS", "foo,bar", "redacted_identifiers", %w[foo bar]],
        [nil, "DD_DYNAMIC_INSTRUMENTATION_REDACTED_IDENTIFIERS", "foo, bar", "redacted_identifiers", %w[foo bar]],
        [nil, "DD_DYNAMIC_INSTRUMENTATION_REDACTED_IDENTIFIERS", "", "redacted_identifiers", %w[]],
        [nil, "DD_DYNAMIC_INSTRUMENTATION_REDACTED_IDENTIFIERS", ",", "redacted_identifiers", %w[]],
        [nil, "DD_DYNAMIC_INSTRUMENTATION_REDACTED_IDENTIFIERS", "~?", "redacted_identifiers", %w[~?]],
        [nil, "DD_DYNAMIC_INSTRUMENTATION_REDACTION_EXCLUDED_IDENTIFIERS", "password", "redaction_excluded_identifiers", %w[password]],
        [nil, "DD_DYNAMIC_INSTRUMENTATION_REDACTION_EXCLUDED_IDENTIFIERS", "password,token", "redaction_excluded_identifiers", %w[password token]],
        [nil, "DD_DYNAMIC_INSTRUMENTATION_REDACTION_EXCLUDED_IDENTIFIERS", "password, token", "redaction_excluded_identifiers", %w[password token]],
        [nil, "DD_DYNAMIC_INSTRUMENTATION_REDACTION_EXCLUDED_IDENTIFIERS", "", "redaction_excluded_identifiers", %w[]],
        [nil, "DD_DYNAMIC_INSTRUMENTATION_REDACTION_EXCLUDED_IDENTIFIERS", ",", "redaction_excluded_identifiers", %w[]],
        [nil, "DD_DYNAMIC_INSTRUMENTATION_REDACTED_TYPES", "foo", "redacted_type_names", %w[foo]],
        [nil, "DD_DYNAMIC_INSTRUMENTATION_REDACTED_TYPES", "foo,bar", "redacted_type_names", %w[foo bar]],
        [nil, "DD_DYNAMIC_INSTRUMENTATION_REDACTED_TYPES", "foo, bar", "redacted_type_names", %w[foo bar]],
        [nil, "DD_DYNAMIC_INSTRUMENTATION_REDACTED_TYPES", "", "redacted_type_names", %w[]],
        [nil, "DD_DYNAMIC_INSTRUMENTATION_REDACTED_TYPES", ",", "redacted_type_names", %w[]],
        [nil, "DD_DYNAMIC_INSTRUMENTATION_REDACTED_TYPES", ".!", "redacted_type_names", %w[.!]],
        [nil, "DD_DYNAMIC_INSTRUMENTATION_MAX_CAPTURE_DEPTH", "5", "max_capture_depth", 5],
        [nil, "DD_DYNAMIC_INSTRUMENTATION_MAX_CAPTURE_COLLECTION_SIZE", "10", "max_capture_collection_size", 10],
        [nil, "DD_DYNAMIC_INSTRUMENTATION_MAX_CAPTURE_STRING_LENGTH", "20", "max_capture_string_length", 20],
        [nil, "DD_DYNAMIC_INSTRUMENTATION_MAX_CAPTURE_ATTRIBUTE_COUNT", "4", "max_capture_attribute_count", 4],
        ["internal", "DD_INTERNAL_DYNAMIC_INSTRUMENTATION_UNTARGETED_TRACE_POINTS", "true", "untargeted_trace_points", true],
        ["internal", "DD_INTERNAL_DYNAMIC_INSTRUMENTATION_UNTARGETED_TRACE_POINTS", "false", "untargeted_trace_points", false],
        ["internal", "DD_INTERNAL_DYNAMIC_INSTRUMENTATION_PROPAGATE_ALL_EXCEPTIONS", "true", "propagate_all_exceptions", true],
        ["internal", "DD_INTERNAL_DYNAMIC_INSTRUMENTATION_PROPAGATE_ALL_EXCEPTIONS", "false", "propagate_all_exceptions", false],
        ["internal", "DD_INTERNAL_DYNAMIC_INSTRUMENTATION_MIN_SEND_INTERVAL", "5.5", "min_send_interval", 5.5],
        ["internal", "DD_INTERNAL_DYNAMIC_INSTRUMENTATION_SNAPSHOT_QUEUE_CAPACITY", "8", "snapshot_queue_capacity", 8],
        ["internal", "DD_INTERNAL_DYNAMIC_INSTRUMENTATION_DEVELOPMENT_ENVIRONMENT", "true", "development", true],
        ["internal", "DD_INTERNAL_DYNAMIC_INSTRUMENTATION_DEVELOPMENT_ENVIRONMENT", "false", "development", false],
        ["internal", "DD_INTERNAL_DYNAMIC_INSTRUMENTATION_MAX_PROCESSING_TIME", "0.25", "max_processing_time", 0.25],
      ].each do |(scope_name_, env_var_name_, env_var_value_, setting_name_, setting_value_)|
        scope_name = scope_name_
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
            scope = if scope_name
              settings.dynamic_instrumentation.public_send(scope_name)
            else
              settings.dynamic_instrumentation
            end

            expect(scope.public_send(setting_name)).to eq setting_value
          end
        end
      end
    end
  end
end
