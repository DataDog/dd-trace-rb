# frozen_string_literal: true

require 'spec_helper'
require 'datadog/open_feature/exposures'

RSpec.describe Datadog::OpenFeature::Exposures::Reporter do
  subject(:reporter) do
    described_class.new(worker: worker, cache: cache, logger: logger, time_provider: time_provider)
  end

  let(:worker) do
    instance_double(
      Datadog::OpenFeature::Exposures::Worker,
      enqueue: true,
      flush: nil,
      stop: nil
    )
  end
  let(:cache) { Datadog::AppSec::APISecurity::LRUCache.new(5) }
  let(:logger) { logger_allowing_debug }
  let(:time_provider) { double('time_provider', now: timestamp) }
  let(:timestamp) { Time.utc(2025, 1, 1) }
  let(:context) { {} }
  let(:result_payload) do
    {
      'flag' => 'boolean-one-of-matches',
      'targetingKey' => 'haley',
      'attributes' => { 'not_matches_flag' => 'False' },
      'result' => {
        'value' => 4,
        'variant' => '4',
        'flagMetadata' => {
          'allocationKey' => '4-for-not-matches',
          'variationType' => 'number',
          'doLog' => true
        }
      }
    }
  end

  describe '#report' do
    context 'when exposure has not been reported' do
      it 'enqueues event with normalized payload' do
        expect(worker).to receive(:enqueue) do |event|
          expect(event.flag_key).to eq('boolean-one-of-matches')
          expect(event.variant_key).to eq('4')
          expect(event.allocation_key).to eq('4-for-not-matches')
          expect(event.subject_id).to eq('haley')
          expect(event.subject_attributes).to eq('not_matches_flag' => 'False')
          expect(event.timestamp).to eq(timestamp)
        end.and_return(true)

        expect(reporter.report(result: result_payload, context: context)).to be(true)
      end
    end

    context 'when exposure was already reported' do
      it 'does not enqueue event again' do
        reporter.report(result: result_payload, context: context)

        expect(worker).not_to receive(:enqueue)
        expect(reporter.report(result: result_payload, context: context)).to be(false)
      end
    end

    context 'when evaluation outcome changes' do
      let(:updated_payload) do
        result_payload.merge(
          'result' => result_payload['result'].merge('variant' => '5')
        )
      end

      it 'enqueues event for new outcome' do
        reporter.report(result: result_payload, context: context)

        expect(worker).to receive(:enqueue).once.and_return(true)
        expect(reporter.report(result: updated_payload, context: context)).to be(true)
      end
    end

    context 'when subject identifier is missing' do
      let(:result_payload) do
        {
          'flag' => 'boolean-one-of-matches',
          'result' => {
            'value' => 4,
            'variant' => '4',
            'flagMetadata' => { 'allocationKey' => '4-for-not-matches' }
          }
        }
      end

      it 'does not enqueue event' do
        expect(worker).not_to receive(:enqueue)
        expect(reporter.report(result: result_payload, context: context)).to be(false)
      end
    end
  end
end


