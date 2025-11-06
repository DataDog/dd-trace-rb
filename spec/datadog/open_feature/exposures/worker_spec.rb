# frozen_string_literal: true

require 'spec_helper'
require 'datadog/open_feature/exposures'
require 'datadog/open_feature/transport/exposures'

RSpec.describe Datadog::OpenFeature::Exposures::Worker do
  subject(:worker) do
    described_class.new(
      settings: settings,
      transport: transport,
      logger: logger,
      flush_interval_seconds: 0.1,
      buffer_limit: 2
    )
  end

  let(:settings) { Datadog::Core::Configuration::Settings.new }
  let(:transport) { instance_double(Datadog::OpenFeature::Transport::Exposures::Transport) }
  let(:response) { instance_double(Datadog::Core::Transport::HTTP::Adapters::Net::Response, ok?: true) }
  let(:logger) { logger_allowing_debug }
  let(:event) do
    Datadog::OpenFeature::Exposures::Models::Event.new(
      timestamp: 1_735_689_600_000,
      allocation: {key: 'control'},
      flag: {key: 'demo-flag'},
      variant: {key: 'v1'},
      subject: {id: 'user-1', attributes: {'plan' => 'pro'}}
    )
  end

  after do
    worker.stop(true)
    worker.join
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

    context 'when buffer has events' do
      it 'starts on demand and processes buffer' do
        sent = 0
        allow(transport).to receive(:send_exposures) do |payload|
          sent += 1
          response
        end

        worker.enqueue(event)

        try_wait_until { worker.running? }
        try_wait_until { sent.positive? }

        expect(sent).to eq(1)
      end
    end
  end

  describe '#enqueue' do
    before do
      allow(worker).to receive(:start)
      allow(transport).to receive(:send_exposures).and_return(response)
    end

    context 'when buffer limit is reached' do
      it 'flushes immediately' do
        worker.enqueue(event)
        worker.enqueue(event)

        try_wait_until { worker.buffer.empty? }

        expect(transport).to have_received(:send_exposures).once
      end
    end
  end

  describe '#flush' do
    before do
      allow(worker).to receive(:start)
      allow(transport).to receive(:send_exposures).and_return(response)
    end

    context 'when buffer has queued events' do
      it 'sends queued events' do
        worker.enqueue(event)

        worker.flush

        expect(transport).to have_received(:send_exposures).once
      end
    end

    context 'when buffer is empty' do
      it 'does not send anything' do
        worker.flush

        expect(transport).not_to have_received(:send_exposures)
      end
    end

    context 'when buffer dropped events' do
      it 'logs debug message' do
        worker.buffer.concat([event, event, event])
        expect_lazy_log(logger, :debug, /OpenFeature: Exposure worker dropped 1 event/)

        worker.flush
      end
    end

    context 'when transport response does not have expected interface' do
      let(:response) { nil }

      it 'logs debug message' do
        expect_lazy_log(logger, :debug, /Send exposures response was not OK/)

        worker.enqueue(event)
        worker.flush
      end
    end

    context 'when transport response is not ok' do
      let(:response) { instance_double(Datadog::Core::Transport::HTTP::Adapters::Net::Response, ok?: false) }

      it 'logs debug message' do
        expect_lazy_log(logger, :debug, /Send exposures response was not OK/)

        worker.enqueue(event)
        worker.flush
      end
    end

    context 'when transport raises an error' do
      it 'logs debug message and swallows the error' do
        allow(transport).to receive(:send_exposures).and_raise(RuntimeError, 'Ooops')
        expect_lazy_log(logger, :debug, /Failed to flush exposure events/)

        worker.enqueue(event)

        expect { worker.flush }.not_to raise_error
      end
    end
  end

  describe '#stop' do
    before do
      allow(worker).to receive(:start)
      allow(transport).to receive(:send_exposures).and_return(response)
    end

    context 'when buffer contains events' do
      it 'flushes remaining events before stopping' do
        worker.enqueue(event)

        expect(transport).to receive(:send_exposures).once
        worker.stop
      end
    end
  end
end

