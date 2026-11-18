# frozen_string_literal: true

require "json"
require "spec_helper"
require_relative "../../../tasks/lib/fixtures/ffe"
require "datadog/open_feature/evaluation_engine"
require "datadog/open_feature/provider"

# The scale suites are opt-in: benchmarks/open_feature_scale_json.rb measures these cases, so this spec
# checks every result the benchmark relies on through the same provider call.
RSpec.describe Datadog::OpenFeature::Provider, "FFE scale suites" do
  fixture_root = File.join(File.expand_path("../../..", __dir__), FfeFixtures::CACHE, FfeFixtures::COMMIT_SHA)
  unless File.directory?(fixture_root)
    raise "FFE fixtures are not cached under #{fixture_root}. Run: bundle exec rake fixtures:ffe:download"
  end

  before do
    allow(Datadog::OpenFeature).to receive(:engine).and_return(engine)
    engine.reconfigure!(File.read(File.join(suite_root, "ufc-config.json")))
  end

  subject(:provider) { described_class.new(experimentation_opt_out_mode: :disabled) }

  let(:engine) { Datadog::OpenFeature::EvaluationEngine.new(telemetry: telemetry, logger: logger) }
  let(:telemetry) { instance_double(Datadog::Core::Telemetry::Component) }
  let(:logger) { instance_double(Datadog::Core::Logger, debug: nil) }

  ["scale", "scale-json"].each do |suite|
    suite_root = File.join(fixture_root, "evaluation-suites", suite)
    case_files = Dir[File.join(suite_root, "cases", "*.json")].sort
    raise "FFE #{suite} suite at #{suite_root} is missing or empty" if case_files.empty?

    context "with the #{suite} suite" do
      let(:suite_root) { suite_root }

      case_files.each do |case_file|
        test_cases = JSON.parse(File.read(case_file)).select { |test_case| FfeFixtures.applicable?(test_case, platform: "ruby") }

        # One example per case file, so each loads the suite configuration once.
        it "evaluates #{File.basename(case_file)}" do
          aggregate_failures do
            test_cases.each_with_index do |test_case, index|
              result = provider.public_send(
                fetch_method(test_case.fetch("variationType")),
                flag_key: test_case.fetch("flag"),
                default_value: test_case.fetch("defaultValue"),
                evaluation_context: ::OpenFeature::SDK::EvaluationContext.new(
                  targeting_key: test_case["targetingKey"], **(test_case.fetch("attributes") || {}),
                ),
              )
              expected = test_case.fetch("result")
              label = "#{File.basename(case_file)}[#{index}] #{test_case.fetch("flag")}"

              expect(result.value).to eq(expected.fetch("value")), "#{label}: unexpected value"
              expect(result.reason).to eq(expected.fetch("reason")), "#{label}: #{result.reason} #{result.error_message}"
              expect(result.variant).to eq(expected["variant"]), "#{label}: unexpected variant" if expected.key?("variant")
              next unless test_case.fetch("variationType") == "JSON"

              repeat = provider.fetch_object_value(
                flag_key: test_case.fetch("flag"),
                default_value: test_case.fetch("defaultValue"),
                evaluation_context: ::OpenFeature::SDK::EvaluationContext.new(
                  targeting_key: test_case["targetingKey"], **(test_case.fetch("attributes") || {}),
                ),
              )
              expect(repeat.value).to be(result.value), "#{label}: repeat evaluation parsed the value again"
              expect(deeply_frozen?(result.value)).to be(true), "#{label}: value is not deeply frozen"
            end
          end
        end
      end
    end
  end

  def deeply_frozen?(value)
    return false unless value.frozen?

    case value
    when Hash then value.all? { |key, item| deeply_frozen?(key) && deeply_frozen?(item) }
    when Array then value.all? { |item| deeply_frozen?(item) }
    else true
    end
  end

  def fetch_method(variation_type)
    case variation_type
    when "BOOLEAN" then :fetch_boolean_value
    when "STRING" then :fetch_string_value
    when "INTEGER" then :fetch_integer_value
    when "NUMERIC" then :fetch_number_value
    when "JSON" then :fetch_object_value
    else raise "Unsupported variation type: #{variation_type}"
    end
  end
end
