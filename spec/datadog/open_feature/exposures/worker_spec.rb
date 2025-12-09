# frozen_string_literal: true

require 'spec_helper'
require 'datadog/open_feature/transport'

RSpec.describe Datadog::OpenFeature::Exposures::Worker do
  after do
    worker.stop(true, 0.1)
    worker.join
  end

  subject(:worker) do
    described_class.new(
      settings: settings,
      transport: transport,
      telemetry: telemetry,
      logger: logger,
      flush_interval_seconds: 0.1,
      buffer_limit: 2
    )
  end

  let(:settings) { Datadog::Core::Configuration::Settings.new }
  let(:transport) { instance_double(Datadog::OpenFeature::Transport::HTTP) }
  let(:telemetry) { instance_double(Datadog::Core::Telemetry::Component) }
  let(:response) { instance_double(Datadog::Core::Transport::HTTP::Adapters::Net::Response, ok?: true) }
  let(:logger) { logger_allowing_debug }
  let(:event) do
    {
      timestamp: 1_735_689_600_000,
      allocation: {key: 'control'},
      flag: {key: 'demo-flag'},
      variant: {key: 'v1'},
      subject: {id: 'user-1', attributes: {'plan' => 'pro'}}
    }
  end

  describe '#start' do
    context 'when worker is disabled' do
      it 'does nothing' do
        allow(worker).to receive(:enabled?).and_return(false)

        worker.start

        expect(worker).not_to be_running
        expect(worker).not_to be_started
      end
    end
  end

  describe '#enqueue' do
    context 'when worker is not started' do
      let(:event_2) do
        {
          timestamp: 1_735_689_600_000,
          allocation: {key: 'control-2'},
          flag: {key: 'demo-flag2'},
          variant: {key: 'v2'},
          subject: {id: 'user-2', attributes: {'plan' => 'pro'}}
        }
      end
      let(:event_3) do
        {
          timestamp: 1_735_689_600_000,
          allocation: {key: 'control-3'},
          flag: {key: 'demo-flag3'},
          variant: {key: 'v3'},
          subject: {id: 'user-3', attributes: {'plan' => 'pro'}}
        }
      end

      it 'starts on demand and processes buffer' do
        batches_sent = 0
        allow(transport).to receive(:send_exposures) do |payload|
          batches_sent += 1
          response
        end

        worker.enqueue(event)
        worker.enqueue(event_2)
        worker.enqueue(event_3)

        try_wait_until { worker.running? }
        try_wait_until { batches_sent.positive? }

        expect(batches_sent).to eq(1)
      end
    end

    context 'when transport response does not have expected interface' do
      before { allow(transport).to receive(:send_exposures).and_return(response) }

      let(:response) { nil }

      it 'logs debug message' do
        worker.enqueue(event)
        try_wait_until { worker.running? }

        expect_lazy_log(logger, :debug, /Resolution details upload response was not OK/)
      end
    end

    context 'when transport response is not ok' do
      before { allow(transport).to receive(:send_exposures).and_return(response) }

      let(:response) { instance_double(Datadog::Core::Transport::HTTP::Adapters::Net::Response, ok?: false) }

      it 'logs debug message' do
        worker.enqueue(event)
        try_wait_until { worker.running? }

        expect_lazy_log(logger, :debug, /Resolution details upload response was not OK/)
      end
    end

    context 'when transport raises an error' do
      before { allow(transport).to receive(:send_exposures).and_raise(error) }

      let(:error) { StandardError.new('Ooops') }

      it 'logs debug message and swallows the error' do
        expect(telemetry).to receive(:report).with(error, description: /Failed to flush resolution details events/)

        worker.enqueue(event)
        try_wait_until { worker.running? }

        expect_lazy_log(logger, :debug, /Failed to flush resolution details events/)
        expect { worker.perform }.not_to raise_error
      end
    end
  end

  describe '#graceful_shutdown' do
    context 'when buffer contains events' do
      before do
        stub_const('Datadog::OpenFeature::Exposures::Worker::GRACEFUL_SHUTDOWN_EXTRA_SECONDS', 0.1)
        stub_const('Datadog::OpenFeature::Exposures::Worker::GRACEFUL_SHUTDOWN_WAIT_INTERVAL_SECONDS', 0.1)
      end

      let(:event_2) do
        {
          timestamp: 1_735_689_600_000,
          allocation: {key: 'control-2'},
          flag: {key: 'demo-flag2'},
          variant: {key: 'v2'},
          subject: {id: 'user-2', attributes: {'plan' => 'pro'}}
        }
      end

      it 'flushes remaining events before stopping' do
        batches_sent = 0
        allow(transport).to receive(:send_exposures) do |payload|
          batches_sent += 1
          response
        end

        worker.enqueue(event)
        try_wait_until { worker.running? }
        try_wait_until { batches_sent.positive? }

        worker.enqueue(event_2)
        worker.graceful_shutdown
        try_wait_until { !worker.running? }

        expect(batches_sent).to eq(2)
      end
    end
  end
end
