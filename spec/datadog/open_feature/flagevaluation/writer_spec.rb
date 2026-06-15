# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'json-schema'
require 'datadog/open_feature/flagevaluation/writer'

RSpec.describe Datadog::OpenFeature::FlagEvaluation::Writer do
  # Real flageval-worker schema (copied from the worker contract). Validates emitted payloads.
  let(:worker_schema_path) { File.expand_path('fixtures/batchedflagevaluations.json', __dir__) }

  # A first/last_evaluation value above the schema's minimum (Oct 2025).
  let(:realistic_eval_ms) { 1_760_000_000_000 }

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

  # #stop must drain + final-flush even when the worker is mid-wait (sleeping). The worker
  # waits on a ConditionVariable up to FLUSH_INTERVAL_SECONDS (10s); #stop must wake it and the
  # transport must actually RECEIVE the drained events — proven without sleeping in the test.
  describe '#stop drains and flushes a sleeping worker' do
    let(:transport) { instance_double(Datadog::OpenFeature::Transport::HTTP) }
    let(:logger) { instance_double(Logger, debug: nil) }

    it 'enqueues, then stop() flushes the queued event to the transport before joining' do
      received = Queue.new
      allow(transport).to receive(:send_flag_evaluations) do |payload|
        received << payload if payload['flagEvaluations']&.any?
      end

      writer = described_class.new(transport: transport, logger: logger)

      # Worker is now alive and waiting on the condition variable (effectively sleeping).
      writer.enqueue(
        flag_key: 'shutdown-flag', variant: 'on', allocation_key: '',
        reason: 'TARGETING_MATCH', targeting_key: 'u1', eval_time_ms: 1_000, attrs: {},
      )

      # stop() must wake the sleeping worker immediately, drain, and final-flush (no 10s wait).
      start = Datadog::Core::Utils::Time.get_time
      writer.stop
      elapsed = Datadog::Core::Utils::Time.get_time - start

      payload = received.pop # blocks until the drained flush arrives; fails the example if it never does
      expect(payload['flagEvaluations'].first['flag']['key']).to eq('shutdown-flag')
      # Shutdown returned well under the 10s flush interval (proves the wait was interrupted).
      expect(elapsed).to be < 9
    end
  end

  # Backpressure must be OBSERVABLE. When the hand-off queue overflows, enqueue increments an
  # observable counter that is emitted (logged) on the next flush — not silently dropped.
  describe '#enqueue queue-overflow backpressure' do
    let(:transport) { instance_double(Datadog::OpenFeature::Transport::HTTP, send_flag_evaluations: nil) }
    let(:logger) { instance_double(Logger, debug: nil) }

    it 'increments dropped_queue_overflow and emits the count on flush' do
      allow_any_instance_of(described_class).to receive(:start_background_thread).and_return(nil)
      writer = described_class.new(transport: transport, logger: logger)

      # Fill the queue to capacity, then overflow it.
      capacity = described_class::QUEUE_SIZE
      event = {
        flag_key: 'f', variant: 'on', allocation_key: '', reason: 'R',
        targeting_key: 't', eval_time_ms: 1, attrs: {},
      }
      capacity.times { writer.enqueue(**event) }
      expect(writer.dropped_queue_overflow).to eq(0)

      # Three more pushes overflow the bounded queue and must be counted.
      3.times { writer.enqueue(**event) }
      expect(writer.dropped_queue_overflow).to eq(3)

      # On flush the count is emitted (logged) and reset to 0 (observable, not silently lost).
      logged = []
      allow(logger).to receive(:debug) { |&blk| logged << blk.call }
      writer.send(:flush_once)

      expect(logged.join).to match(/queue_overflow=3/)
      expect(writer.dropped_queue_overflow).to eq(0)
    end
  end

  # Emitted payload MUST validate against the real flageval-worker JSON schema — for BOTH
  # full-tier and degraded-tier rows. variant/allocation serialize as {"key": ...} objects.
  describe 'emitted payload conforms to the flageval-worker JSON schema' do
    let(:logger) { instance_double(Logger, debug: nil) }

    def captured_payload
      payload = nil
      transport = instance_double(Datadog::OpenFeature::Transport::HTTP)
      allow(transport).to receive(:send_flag_evaluations) { |p| payload = p }
      allow_any_instance_of(described_class).to receive(:start_background_thread).and_return(nil)
      writer = described_class.new(transport: transport, logger: logger)
      yield writer
      writer.send(:drain_and_flush)
      payload
    end

    it 'validates a full-tier row (variant/allocation/targeting_key/context all present)' do
      payload = captured_payload do |writer|
        writer.enqueue(
          flag_key: 'schema-flag', variant: 'on', allocation_key: 'alloc-1',
          reason: 'TARGETING_MATCH', targeting_key: 'user-42',
          eval_time_ms: realistic_eval_ms, attrs: {'env' => 'prod', 'tier' => 'gold'},
        )
      end

      row = payload['flagEvaluations'].first
      # Structural assertions: objects, not bare strings.
      expect(row['variant']).to eq('key' => 'on')
      expect(row['allocation']).to eq('key' => 'alloc-1')
      expect(row['targeting_key']).to eq('user-42')
      expect(row['context']).to eq('evaluation' => {'env' => 'prod', 'tier' => 'gold'})

      errors = JSON::Validator.fully_validate(worker_schema_path, JSON.parse(JSON.generate(payload)))
      expect(errors).to be_empty, "schema errors: #{errors.join("\n")}"
    end

    it 'validates a degraded-tier row (no targeting_key, no context)' do
      payload = captured_payload do |writer|
        # Force overflow into the degraded tier with a tiny-capped aggregator.
        small = Datadog::OpenFeature::FlagEvaluation::Aggregator.new(global_cap: 1, per_flag_cap: 1, degraded_cap: 10)
        writer.instance_variable_set(:@aggregator, small)
        writer.enqueue(
          flag_key: 'deg-flag', variant: 'a', allocation_key: 'alloc-x', reason: 'SPLIT',
          targeting_key: 'u1', eval_time_ms: realistic_eval_ms, attrs: {'x' => 1},
        )
        writer.enqueue(
          flag_key: 'deg-flag', variant: 'a', allocation_key: 'alloc-x', reason: 'SPLIT',
          targeting_key: 'u2', eval_time_ms: realistic_eval_ms, attrs: {'x' => 2},
        )
      end

      degraded_row = payload['flagEvaluations'].find { |r| !r.key?('targeting_key') && !r.key?('context') }
      expect(degraded_row).not_to be_nil
      expect(degraded_row['variant']).to eq('key' => 'a')
      expect(degraded_row['allocation']).to eq('key' => 'alloc-x')

      errors = JSON::Validator.fully_validate(worker_schema_path, JSON.parse(JSON.generate(payload)))
      expect(errors).to be_empty, "schema errors: #{errors.join("\n")}"
    end

    # The emitted context must hold the PRUNED attrs (oversized strings removed, <=256 fields),
    # not the raw attrs. Proven by inspecting the emitted payload, not the aggregator internals.
    it 'emits PRUNED context attrs in the payload (oversized strings removed, capped at 256 fields)' do
      raw = {'keep' => 'ok', 'toobig' => 'x' * 257}
      300.times { |i| raw["k#{format("%03d", i)}"] = 'v' }

      payload = captured_payload do |writer|
        writer.enqueue(
          flag_key: 'prune-flag', variant: 'on', allocation_key: '',
          reason: 'STATIC', targeting_key: 't', eval_time_ms: realistic_eval_ms, attrs: raw,
        )
      end

      emitted = payload['flagEvaluations'].first['context']['evaluation']
      expect(emitted.size).to eq(256)              # capped
      expect(emitted).not_to have_key('toobig')    # oversized string removed
      # Deterministic subset = sorted-first 256 keys (so 'k000'..'k253' kept, 'keep'/'k254'+ cut).
      expect(emitted).to have_key('k000')
      expect(emitted).not_to have_key('k299')
    end
  end

  # The aggregator's degraded-overflow count must be EMITTED before reset (not reset-without-emit).
  describe '#flush_once emits degraded-overflow drops' do
    let(:transport) { instance_double(Datadog::OpenFeature::Transport::HTTP, send_flag_evaluations: nil) }
    let(:logger) { instance_double(Logger) }

    it 'logs the degraded_overflow count returned in the aggregator snapshot' do
      allow_any_instance_of(described_class).to receive(:start_background_thread).and_return(nil)
      writer = described_class.new(transport: transport, logger: logger)

      # Inject an aggregator whose flush reports a degraded-overflow drop.
      fake_aggregator = instance_double(Datadog::OpenFeature::FlagEvaluation::Aggregator)
      allow(fake_aggregator).to receive(:flush_and_reset).and_return(
        {full: {}, degraded: {}, dropped_degraded_overflow: 7}
      )
      writer.instance_variable_set(:@aggregator, fake_aggregator)

      logged = []
      allow(logger).to receive(:debug) { |&blk| logged << blk.call }

      writer.send(:flush_once)

      expect(logged.join).to match(/degraded_overflow=7/)
    end
  end
end
