# frozen_string_literal: true

require 'spec_helper'
require 'datadog/open_feature/exposures/models/event'

RSpec.describe Datadog::OpenFeature::Exposures::Models::Event do
  describe '.build' do
    before { allow(Datadog::Core::Utils::Time).to receive(:now).and_return(now) }

    let(:now) { Time.utc(2025, 1, 1, 0, 0, 0) }
    let(:event) { described_class.build(result, flag_key: 'feature_flag', context: context) }
    let(:result) do
      Datadog::OpenFeature::Binding::ResolutionDetails.new(
        value: 4,
        allocation_key: '4-for-john-doe',
        variant: '4',
        flag_metadata: {
          'allocationKey' => '4-for-john-doe',
          'variationType' => 'number',
          'doLog' => true
        },
        do_log: true
      )
    end
    let(:context) do
      instance_double(
        'OpenFeature::SDK::EvaluationContext',
        targeting_key: 'john-doe',
        fields: {
          'targeting_key' => 'john-doe',
          'age' => 21,
          'active' => true,
          'ratio' => 7.5,
          'nickname' => 'johnny',
          'ignored_hash' => {foo: 'bar'},
          'ignored_array' => [1, 2]
        }
      )
    end

    context 'when context contains nested fields' do
      let(:expected) do
        {
          timestamp: 1_735_689_600_000,
          allocation: {
            key: '4-for-john-doe'
          },
          flag: {
            key: 'feature_flag'
          },
          variant: {
            key: '4'
          },
          subject: {
            id: 'john-doe',
            attributes: {
              'age' => 21,
              'active' => true,
              'ratio' => 7.5,
              'nickname' => 'johnny'
            }
          }
        }
      end

      it 'builds exposure event and extracts attributes without nested fields' do
        expect(event).to be_a(described_class)
        expect(event.flag_key).to eq('feature_flag')
        expect(event.targeting_key).to eq('john-doe')
        expect(event.allocation_key).to eq('4-for-john-doe')
        expect(event.variation_key).to eq('4')
        expect(event.to_h).to eq(expected)
      end
    end

    context 'when context does not contain extra fields' do
      let(:context) do
        instance_double(
          'OpenFeature::SDK::EvaluationContext', targeting_key: 'john-doe', fields: {'targeting_key' => 'john-doe'}
        )
      end
      let(:expected) do
        {
          timestamp: 1_735_689_600_000,
          allocation: {
            key: '4-for-john-doe'
          },
          flag: {
            key: 'feature_flag'
          },
          variant: {
            key: '4'
          },
          subject: {
            id: 'john-doe',
            attributes: {}
          }
        }
      end

      it 'builds exposure event and extracts attributes without nested fields' do
        expect(event.to_h).to eq(expected)
      end
    end
  end
end
