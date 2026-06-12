# frozen_string_literal: true

require 'spec_helper'
require 'datadog/open_feature/flagevaluation/writer'

RSpec.describe Datadog::OpenFeature::FlagEvaluation::Writer do
  # Regression guard: rescue inside until...end (without begin) is a Ruby SyntaxError.
  # If writer.rb fails to parse, the EVP component silently falls back to nil and no
  # events are ever delivered to mock-intake.
  it 'loads without SyntaxError' do
    expect { described_class }.not_to raise_error
  end

  describe '#enqueue / background flush integration' do
    let(:transport) { instance_double(Datadog::OpenFeature::Transport::HTTP) }
    let(:logger) { instance_double(Logger, debug: nil) }

    it 'enqueues an event and flushes it via transport' do
      allow(transport).to receive(:send_flag_evaluations)

      writer = nil
      # Stub the background thread so we control flush timing
      allow_any_instance_of(described_class).to receive(:start_background_thread).and_return(nil)
      writer = described_class.new(transport: transport, logger: logger)

      writer.enqueue(
        flag_key: 'my-flag',
        variant: 'on',
        allocation_key: '',
        reason: 'TARGETING_MATCH',
        targeting_key: 'user-1',
        eval_time_ms: 1_234_567_890_000,
        attrs: {},
      )

      # Flush manually (skip background thread)
      writer.send(:drain_and_flush)

      expect(transport).to have_received(:send_flag_evaluations) do |payload|
        expect(payload['flagEvaluations']).not_to be_empty
        expect(payload['flagEvaluations'].first['flag']['key']).to eq('my-flag')
      end
    end
  end
end
