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
        ["internal", "min_send_interval", 5],
        ["internal", "development", true],
        ["internal", "development", false],
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
        [nil, "max_time_to_serialize_ms", 300],
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

    context "default values" do
      around do |example|
        ClimateControl.modify(
          "DD_DYNAMIC_INSTRUMENTATION_CAPTURE_TIMEOUT_MS" => nil,
          "DD_DYNAMIC_INSTRUMENTATION_MAX_TIME_TO_SERIALIZE" => nil,
        ) do
          example.run
        end
      end

      it "defaults max_time_to_serialize_ms to 150" do
        expect(settings.dynamic_instrumentation.max_time_to_serialize_ms).to eq(150)
      end
    end

    context "max_time_to_serialize_ms validation" do
      it "accepts zero as a valid exhausted-budget sentinel" do
        settings.dynamic_instrumentation.max_time_to_serialize_ms = 0
        expect(settings.dynamic_instrumentation.max_time_to_serialize_ms).to eq(0)
      end

      it "raises ArgumentError for a negative value" do
        expect do
          settings.dynamic_instrumentation.max_time_to_serialize_ms = -5
        end.to raise_error(ArgumentError, /must not be negative/)
      end
    end

    context "environment variable configuration" do
      [
        ["DD_DYNAMIC_INSTRUMENTATION_ENABLED", "true", "enabled", true],
        ["DD_DYNAMIC_INSTRUMENTATION_ENABLED", "false", "enabled", false],
        ["DD_DYNAMIC_INSTRUMENTATION_ENABLED", nil, "enabled", false],
        ["DD_DYNAMIC_INSTRUMENTATION_CAPTURE_TIMEOUT_MS", "300", "max_time_to_serialize_ms", 300],
        ["DD_DYNAMIC_INSTRUMENTATION_CAPTURE_TIMEOUT", "300", "max_time_to_serialize_ms", 300],
        ["DD_DYNAMIC_INSTRUMENTATION_EVALUATION_TIMEOUT_MS", "10", "max_time_to_evaluate_ms", 10],
        ["DD_DYNAMIC_INSTRUMENTATION_EVALUATION_TIMEOUT_MS", nil, "max_time_to_evaluate_ms", 50],
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
      context "when DD_DYNAMIC_INSTRUMENTATION_EVALUATION_TIMEOUT_MS=-5" do
        around do |example|
          ClimateControl.modify("DD_DYNAMIC_INSTRUMENTATION_EVALUATION_TIMEOUT_MS" => "-5") do
            example.run
          end
        end

        it "raises ArgumentError for a negative value" do
          expect { settings.dynamic_instrumentation.max_time_to_evaluate_ms }
            .to raise_error(ArgumentError, /must not be negative/)
        end
      end
    end

    context "legacy capture-timeout name" do
      around do |example|
        ClimateControl.modify(
          "DD_DYNAMIC_INSTRUMENTATION_MAX_TIME_TO_SERIALIZE" => "250",
          "DD_DYNAMIC_INSTRUMENTATION_CAPTURE_TIMEOUT_MS" => nil,
        ) do
          example.run
        end
      end

      it "resolves the legacy name as the deprecated budget fallback" do
        expect(settings.dynamic_instrumentation.max_time_to_serialize_ms).to eq 250
      end

      it "logs a deprecation pointing at the canonical name" do
        deprecation = nil
        allow(Datadog::Core).to receive(:log_deprecation) do |**_kwargs, &message|
          deprecation = message&.call
        end

        settings.dynamic_instrumentation.max_time_to_serialize_ms

        expect(deprecation).to include("DD_DYNAMIC_INSTRUMENTATION_MAX_TIME_TO_SERIALIZE environment variable is deprecated")
        expect(deprecation).to include("use DD_DYNAMIC_INSTRUMENTATION_CAPTURE_TIMEOUT_MS instead")
      end
    end

    context "when both capture-timeout names are set" do
      around do |example|
        ClimateControl.modify(
          "DD_DYNAMIC_INSTRUMENTATION_MAX_TIME_TO_SERIALIZE" => "250",
          "DD_DYNAMIC_INSTRUMENTATION_CAPTURE_TIMEOUT_MS" => "300",
        ) do
          example.run
        end
      end

      it "prefers the canonical name over the legacy name" do
        expect(settings.dynamic_instrumentation.max_time_to_serialize_ms).to eq 300
      end
    end

    context "when the legacy name and code configuration are both present" do
      around do |example|
        ClimateControl.modify(
          "DD_DYNAMIC_INSTRUMENTATION_MAX_TIME_TO_SERIALIZE" => "250",
          "DD_DYNAMIC_INSTRUMENTATION_CAPTURE_TIMEOUT_MS" => nil,
        ) do
          example.run
        end
      end

      it "prefers the configured value over the legacy name" do
        settings.dynamic_instrumentation.max_time_to_serialize_ms = 400
        expect(settings.dynamic_instrumentation.max_time_to_serialize_ms).to eq 400
      end
    end

    context "when the legacy name is not an integer" do
      around do |example|
        ClimateControl.modify(
          "DD_DYNAMIC_INSTRUMENTATION_MAX_TIME_TO_SERIALIZE" => "abc",
          "DD_DYNAMIC_INSTRUMENTATION_CAPTURE_TIMEOUT_MS" => nil,
        ) do
          example.run
        end
      end

      it "raises ArgumentError naming the legacy variable" do
        expect do
          settings.dynamic_instrumentation.max_time_to_serialize_ms
        end.to raise_error(ArgumentError, /DD_DYNAMIC_INSTRUMENTATION_MAX_TIME_TO_SERIALIZE/)
      end
    end

    context "when the legacy name is negative" do
      around do |example|
        ClimateControl.modify(
          "DD_DYNAMIC_INSTRUMENTATION_MAX_TIME_TO_SERIALIZE" => "-5",
          "DD_DYNAMIC_INSTRUMENTATION_CAPTURE_TIMEOUT_MS" => nil,
        ) do
          example.run
        end
      end

      it "raises ArgumentError for the negative value" do
        expect do
          settings.dynamic_instrumentation.max_time_to_serialize_ms
        end.to raise_error(ArgumentError, /must not be negative/)
      end
    end

    context "when the canonical name is set alongside an invalid legacy name" do
      ["abc", "-5"].each do |legacy_value|
        around do |example|
          ClimateControl.modify(
            "DD_DYNAMIC_INSTRUMENTATION_MAX_TIME_TO_SERIALIZE" => legacy_value,
            "DD_DYNAMIC_INSTRUMENTATION_CAPTURE_TIMEOUT_MS" => "300",
          ) do
            example.run
          end
        end

        it "resolves the canonical value without raising for the legacy value #{legacy_value}" do
          expect(settings.dynamic_instrumentation.max_time_to_serialize_ms).to eq 300
        end
      end
    end

    context "when the canonical alias is set alongside an invalid legacy name" do
      around do |example|
        ClimateControl.modify(
          "DD_DYNAMIC_INSTRUMENTATION_MAX_TIME_TO_SERIALIZE" => "abc",
          "DD_DYNAMIC_INSTRUMENTATION_CAPTURE_TIMEOUT" => "300",
        ) do
          example.run
        end
      end

      it "resolves the alias value without raising for the legacy value" do
        expect(settings.dynamic_instrumentation.max_time_to_serialize_ms).to eq 300
      end
    end

    context "when the legacy name is set only in local stable configuration" do
      before do
        allow(Datadog::Core::Configuration::StableConfig).to receive(:configuration)
          .and_return(local: {config: {"DD_DYNAMIC_INSTRUMENTATION_MAX_TIME_TO_SERIALIZE" => "250"}})
      end

      around do |example|
        ClimateControl.modify(
          "DD_DYNAMIC_INSTRUMENTATION_MAX_TIME_TO_SERIALIZE" => nil,
          "DD_DYNAMIC_INSTRUMENTATION_CAPTURE_TIMEOUT_MS" => nil,
        ) do
          example.run
        end
      end

      it "applies the legacy value from stable configuration" do
        expect(settings.dynamic_instrumentation.max_time_to_serialize_ms).to eq 250
      end
    end

    context "when the canonical name is set in fleet stable configuration alongside an invalid legacy name" do
      before do
        allow(Datadog::Core::Configuration::StableConfig).to receive(:configuration)
          .and_return(fleet: {config: {"DD_DYNAMIC_INSTRUMENTATION_CAPTURE_TIMEOUT_MS" => "300"}})
      end

      around do |example|
        ClimateControl.modify(
          "DD_DYNAMIC_INSTRUMENTATION_MAX_TIME_TO_SERIALIZE" => "abc",
          "DD_DYNAMIC_INSTRUMENTATION_CAPTURE_TIMEOUT_MS" => nil,
        ) do
          example.run
        end
      end

      it "resolves the fleet value without raising for the legacy value" do
        expect(settings.dynamic_instrumentation.max_time_to_serialize_ms).to eq 300
      end
    end
    context "max_time_to_evaluate_ms validation" do
      it "accepts zero as a valid exhausted-budget sentinel" do
        settings.dynamic_instrumentation.max_time_to_evaluate_ms = 0
        expect(settings.dynamic_instrumentation.max_time_to_evaluate_ms).to eq(0)
      end

      it "raises ArgumentError for a negative value" do
        expect do
          settings.dynamic_instrumentation.max_time_to_evaluate_ms = -5
        end.to raise_error(ArgumentError, /must not be negative/)
      end
    end
  end
end
