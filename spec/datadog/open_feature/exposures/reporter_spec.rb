# frozen_string_literal: true

require 'spec_helper'
require 'datadog/open_feature/exposures/reporter'

RSpec.describe Datadog::OpenFeature::Exposures::Reporter do
  before do
    allow(Datadog::OpenFeature::Exposures::Deduplicator).to receive(:new).and_return(deduplicator)
  end

  subject(:reporter) { described_class.new(worker, telemetry: telemetry, logger: logger) }

  let(:worker) { instance_double(Datadog::OpenFeature::Exposures::Worker) }
  let(:telemetry) { instance_double(Datadog::Core::Telemetry::Component) }
  let(:logger) { logger_allowing_debug }

  let(:deduplicator) { instance_double(Datadog::OpenFeature::Exposures::Deduplicator) }
  let(:context) do
    instance_double(
      'OpenFeature::SDK::EvaluationContext', targeting_key: 'john-doe', fields: {'targeting_key' => 'john-doe'}
    )
  end
  let(:result) do
    Datadog::OpenFeature::ResolutionDetails.new(
      value: 4,
      allocation_key: '4-for-john-doe',
      variant: '4',
      flag_metadata: {
        'allocationKey' => '4-for-john-doe',
        'variationType' => 'number',
        'doLog' => true
      },
      log?: true,
      error?: false
    )
  end

  describe '#report' do
    context 'when exposure has not been reported' do
      before { allow(deduplicator).to receive(:duplicate?).and_return(false) }

      it 'enqueues event' do
        expect(worker).to receive(:enqueue).and_return(true)
        expect(reporter.report(result, flag_key: 'feature_flag', context: context)).to be(true)
      end
    end

    context 'when exposure was already reported' do
      before { allow(deduplicator).to receive(:duplicate?).and_return(true) }

      it 'does not enqueue event again' do
        expect(worker).not_to receive(:enqueue)
        expect(reporter.report(result, flag_key: 'feature_flag', context: context)).to be(false)
      end
    end

    context 'when worker enqueue fails' do
      before do
        allow(deduplicator).to receive(:duplicate?).and_return(false)
        allow(worker).to receive(:enqueue).and_raise(error)
      end

      let(:error) { StandardError.new('Oops') }

      it 'returns false and logs debug message' do
        expect(telemetry).to receive(:report).with(error, description: /Failed to report resolution details/)
        expect_lazy_log(logger, :debug, /Failed to report resolution details: StandardError: Oops/)
        expect(reporter.report(result, flag_key: 'feature_flag', context: context)).to be(false)
      end
    end

    context 'when event should not be reported' do
      let(:result) do
        Datadog::OpenFeature::ResolutionDetails.new(
          value: 4,
          allocation_key: '4-for-john-doe',
          flag_metadata: {},
          log?: false,
          error?: true
        )
      end

      it 'skips enqueueing exposure' do
        expect(deduplicator).not_to receive(:duplicate?)
        expect(worker).not_to receive(:enqueue)

        expect(reporter.report(result, flag_key: 'feature_flag', context: context)).to be(false)
      end
    end

    context 'when evaluation context is nil' do
      it 'skips enqueueing exposure' do
        expect(deduplicator).not_to receive(:duplicate?)
        expect(worker).not_to receive(:enqueue)

        expect(reporter.report(result, flag_key: 'feature_flag', context: nil)).to be(false)
      end
    end
  end
end
