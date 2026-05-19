# frozen_string_literal: true

require 'json'

require 'datadog/open_feature/native_evaluator'

RSpec.describe Datadog::OpenFeature::NativeEvaluator do
  fixture_root = File.expand_path('ffe-system-test-data', __dir__)
  fixture_files = Dir[File.join(fixture_root, 'evaluation-cases', '*.json')].sort

  raise 'FFE fixture submodule is missing or empty' if fixture_files.empty?

  let(:configuration) { File.read(File.join(fixture_root, 'ufc-config.json')) }
  let(:evaluator) { described_class.new(configuration) }

  describe 'canonical FFE fixtures' do
    fixture_files.each do |fixture_file|
      JSON.parse(File.read(fixture_file)).each_with_index do |test_case, index|
        it "evaluates #{File.basename(fixture_file)}[#{index}]" do
          result = evaluator.get_assignment(
            test_case.fetch('flag'),
            default_value: test_case.fetch('defaultValue'),
            expected_type: expected_type(test_case.fetch('variationType')),
            context: evaluation_context(test_case)
          )

          expected = test_case.fetch('result')

          expect(result.value).to eq(expected.fetch('value'))
          expect(result.reason).to eq(expected.fetch('reason'))
          expect(result.variant).to eq(expected['variant'])
          expect(result.error_code).to eq(expected['errorCode'])
        end
      end
    end
  end

  def expected_type(variation_type)
    case variation_type
    when 'BOOLEAN'
      :boolean
    when 'STRING'
      :string
    when 'INTEGER'
      :integer
    when 'NUMERIC'
      :number
    when 'JSON'
      :object
    else
      raise "Unsupported variation type: #{variation_type}"
    end
  end

  def evaluation_context(test_case)
    {'targeting_key' => test_case['targetingKey']}.merge(test_case.fetch('attributes') || {})
  end
end
