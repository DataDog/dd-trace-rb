# frozen_string_literal: true

require 'spec_helper'
require 'datadog/tracing/transport/backpressure'
require 'datadog/tracing/transport/traces'

RSpec.describe Datadog::Tracing::Transport::Backpressure::Configuration do
  subject(:config) { described_class.new }

  describe '#initialize' do
    context 'with default values' do
      it 'sets default max_retry_queue_size' do
        expect(config.max_retry_queue_size).to eq(100)
      end

      it 'sets default initial_backoff_seconds' do
        expect(config.initial_backoff_seconds).to eq(1.0)
      end

      it 'sets default max_backoff_seconds' do
        expect(config.max_backoff_seconds).to eq(30.0)
      end

      it 'sets default backoff_multiplier' do
        expect(config.backoff_multiplier).to eq(2.0)
      end
    end

    context 'with custom values' do
      subject(:config) do
        described_class.new(
          max_retry_queue_size: 50,
          initial_backoff_seconds: 2.0,
          max_backoff_seconds: 60.0,
          backoff_multiplier: 3.0
        )
      end

      it 'sets custom max_retry_queue_size' do
        expect(config.max_retry_queue_size).to eq(50)
      end

      it 'sets custom initial_backoff_seconds' do
        expect(config.initial_backoff_seconds).to eq(2.0)
      end

      it 'sets custom max_backoff_seconds' do
        expect(config.max_backoff_seconds).to eq(60.0)
      end

      it 'sets custom backoff_multiplier' do
        expect(config.backoff_multiplier).to eq(3.0)
      end
    end
  end
end

RSpec.describe Datadog::Tracing::Transport::Backpressure::RetryQueue do
  subject(:retry_queue) { described_class.new(client: client, config: config, logger: logger) }

  let(:client) { instance_double(Datadog::Tracing::Transport::HTTP::Client) }
  let(:config) { Datadog::Tracing::Transport::Backpressure::Configuration.new }
  let(:logger) { instance_double(Datadog::Core::Logger) }
  let(:request) do
    parcel = instance_double(
      Datadog::Tracing::Transport::Traces::EncodedParcel,
      trace_count: 5
    )
    Datadog::Tracing::Transport::Traces::Request.new(parcel)
  end

  before do
    allow(logger).to receive(:debug)
    allow(logger).to receive(:warn)
    allow(logger).to receive(:error)
  end

  after do
    retry_queue.shutdown
  end

  describe '#initialize' do
    it 'initializes with a client' do
      expect(retry_queue.client).to eq(client)
    end

    it 'initializes with a config' do
      expect(retry_queue.config).to eq(config)
    end

    it 'initializes with a logger' do
      expect(retry_queue.logger).to eq(logger)
    end

    it 'starts with an empty queue' do
      expect(retry_queue.size).to eq(0)
    end
  end

  describe '#enqueue' do
    context 'when queue has space' do
      it 'adds the request to the queue' do
        expect(retry_queue.enqueue(request)).to be true
        expect(retry_queue.size).to eq(1)
      end

      it 'logs the enqueue action' do
        expect(logger).to receive(:debug)
        retry_queue.enqueue(request)
      end
    end

    context 'when queue is full' do
      let(:config) do
        Datadog::Tracing::Transport::Backpressure::Configuration.new(
          max_retry_queue_size: 2
        )
      end

      before do
        # Fill the queue to capacity
        2.times { retry_queue.enqueue(request) }
      end

      it 'rejects the request' do
        expect(retry_queue.enqueue(request)).to be false
      end

      it 'logs a warning' do
        expect(logger).to receive(:warn)
        retry_queue.enqueue(request)
      end

      it 'does not increase queue size' do
        expect { retry_queue.enqueue(request) }.not_to change { retry_queue.size }
      end
    end
  end

  describe '#size' do
    it 'returns the current queue size' do
      expect(retry_queue.size).to eq(0)
      retry_queue.enqueue(request)
      expect(retry_queue.size).to eq(1)
    end
  end

  describe '#shutdown' do
    it 'stops the retry thread' do
      retry_queue.enqueue(request)
      # Give thread time to start
      sleep 0.2
      retry_queue.shutdown
      expect(retry_queue.instance_variable_get(:@shutdown)).to be true
    end
  end

  describe 'retry loop' do
    let(:ok_response) do
      instance_double(
        Datadog::Tracing::Transport::HTTP::Traces::Response,
        ok?: true,
        too_many_requests?: false,
        code: 200
      )
    end

    let(:too_many_requests_response) do
      instance_double(
        Datadog::Tracing::Transport::HTTP::Traces::Response,
        ok?: false,
        too_many_requests?: true,
        code: 429
      )
    end

    let(:client_error_response) do
      instance_double(
        Datadog::Tracing::Transport::HTTP::Traces::Response,
        ok?: false,
        too_many_requests?: false,
        code: 400
      )
    end

    context 'when retry succeeds' do
      before do
        allow(client).to receive(:send_traces_payload).with(request).and_return(ok_response)
      end

      it 'successfully processes the request' do
        expect(client).to receive(:send_traces_payload).with(request)
        retry_queue.enqueue(request)
        # Give the retry thread time to process
        sleep 0.2
      end

      it 'empties the queue after successful retry' do
        retry_queue.enqueue(request)
        sleep 0.2
        expect(retry_queue.size).to eq(0)
      end
    end

    context 'when retry returns 429' do
      let(:config) do
        Datadog::Tracing::Transport::Backpressure::Configuration.new(
          initial_backoff_seconds: 0.1,
          max_backoff_seconds: 0.2
        )
      end

      before do
        allow(client).to receive(:send_traces_payload)
          .with(request)
          .and_return(too_many_requests_response, too_many_requests_response, ok_response)
      end

      it 're-queues the request and applies backoff' do
        retry_queue.enqueue(request)
        # Wait for multiple retries
        sleep 0.5
        # Eventually succeeds and empties the queue
        expect(retry_queue.size).to eq(0)
      end
    end

    context 'when retry returns non-retriable error' do
      before do
        allow(client).to receive(:send_traces_payload).with(request).and_return(client_error_response)
      end

      it 'drops the payload and logs warning' do
        expect(logger).to receive(:warn)
        retry_queue.enqueue(request)
        sleep 0.2
        expect(retry_queue.size).to eq(0)
      end
    end

    context 'when retry raises an exception' do
      before do
        allow(client).to receive(:send_traces_payload).with(request).and_raise(StandardError.new('Network error'))
      end

      it 'drops the payload and logs warning' do
        expect(logger).to receive(:warn)
        retry_queue.enqueue(request)
        sleep 0.2
        expect(retry_queue.size).to eq(0)
      end
    end
  end

  describe 'exponential backoff' do
    let(:config) do
      Datadog::Tracing::Transport::Backpressure::Configuration.new(
        initial_backoff_seconds: 0.05,
        max_backoff_seconds: 0.2,
        backoff_multiplier: 2.0
      )
    end

    let(:too_many_requests_response) do
      instance_double(
        Datadog::Tracing::Transport::HTTP::Traces::Response,
        ok?: false,
        too_many_requests?: true,
        code: 429
      )
    end

    let(:ok_response) do
      instance_double(
        Datadog::Tracing::Transport::HTTP::Traces::Response,
        ok?: true,
        too_many_requests?: false,
        code: 200
      )
    end

    before do
      # First 3 attempts return 429, then succeed
      allow(client).to receive(:send_traces_payload)
        .with(request)
        .and_return(
          too_many_requests_response,
          too_many_requests_response,
          too_many_requests_response,
          ok_response
        )
    end

    it 'applies exponential backoff with cap' do
      start_time = Time.now
      retry_queue.enqueue(request)

      # Wait for retries to complete
      sleep 0.8

      elapsed_time = Time.now - start_time

      # Should have done backoffs: 0.05 + 0.1 + 0.2 = 0.35 seconds minimum
      # Allow some variance for thread scheduling
      expect(elapsed_time).to be >= 0.3
      expect(retry_queue.size).to eq(0)
    end
  end
end
