# frozen_string_literal: true

require "json"
require "spec_helper"
require_relative "../../../tasks/lib/fixtures/ffe"
require "datadog/open_feature/native_evaluator"

RSpec.describe Datadog::OpenFeature::NativeEvaluator, "canonical FFE fixtures" do
  fixture_root = File.join(File.expand_path("../../..", __dir__), FfeFixtures::CACHE, FfeFixtures::COMMIT_SHA)
  unless File.directory?(fixture_root)
    raise "FFE fixtures are not cached under #{fixture_root}. Run: bundle exec rake fixtures:ffe:download"
  end

  fixture_files = Dir[File.join(fixture_root, "evaluation-cases", "*.json")].sort
  raise "Canonical FFE corpus at #{fixture_root} is missing or empty" if fixture_files.empty?

  subject(:evaluator) { described_class.new(configuration) }

  let(:configuration) { File.read(File.join(fixture_root, "ufc-config.json")) }

  fixture_cases = fixture_files.flat_map do |fixture_file|
    JSON.parse(File.read(fixture_file)).each_with_index.map do |test_case, index|
      [test_case, "#{File.basename(fixture_file)}[#{index}]"]
    end
  end
  applicable, excluded = fixture_cases.partition { |test_case, _| FfeFixtures.applicable?(test_case, platform: "ruby") }

  {
    nil => :disabled,
    "experimentationOptOutImmediate" => :immediate,
    "experimentationOptOutFutureExperimentsOnly" => :future_experiments_only,
  }.each do |capability, mode|
    selected = applicable.select { |test_case, _| capability.nil? || test_case.fetch("capabilities", {}).key?(capability) }
    excluded_count = excluded.count { |test_case, _| capability.nil? || test_case.fetch("capabilities", {}).key?(capability) }
    if capability && selected.empty?
      raise "Canonical FFE capability #{capability} has no applicable Ruby cases"
    end

    RSpec.configuration.reporter.message(
      "FFE fixtures #{FfeFixtures::COMMIT_SHA}, core #{capability || "baseline"}: " \
        "#{selected.length} applicable, #{excluded_count} excluded",
    )

    context "in #{mode} mode" do
      before do
        native_method = case mode
        when :immediate then :get_assignment_with_options
        when :future_experiments_only then :get_assignment_with_opt_out_mode
        else :get_assignment
        end
        unless Datadog::Core::FeatureFlags::Configuration.method_defined?(native_method)
          skip "Requires a libdatadog build with #{mode} opt-out support"
        end
      end

      selected.each do |test_case, name|
        it "evaluates #{name}" do
          result = evaluator.get_assignment(
            test_case.fetch("flag"),
            default_value: test_case.fetch("defaultValue"),
            expected_type: expected_type(test_case.fetch("variationType")),
            context: {"targeting_key" => test_case["targetingKey"]}.merge(test_case.fetch("attributes") || {}),
            experimentation_opt_out_mode: mode,
          )
          expected = capability ? test_case.fetch("capabilities").fetch(capability) : test_case.fetch("result")

          expect(result.value).to eq(expected.fetch("value"))
          expect(result.reason).to eq(expected.fetch("reason"))
          expect(result.variant).to eq(expected["variant"]) if expected.key?("variant")
          expect(result.serial_id).to eq(expected["serialId"]) if expected.key?("serialId")
          expect(result.log?).to eq(expected["doLog"]) if expected.key?("doLog")
          if expected.key?("errorCode") || expected.fetch("reason") != "ERROR"
            expect(result.error_code).to eq(expected["errorCode"])
          end
          expect(result.error?).to eq(expected.fetch("reason") == "ERROR")
        end
      end
    end
  end

  def expected_type(variation_type)
    case variation_type
    when "BOOLEAN" then :boolean
    when "STRING" then :string
    when "INTEGER" then :integer
    when "NUMERIC" then :number
    when "JSON" then :object
    else raise "Unsupported variation type: #{variation_type}"
    end
  end
end
