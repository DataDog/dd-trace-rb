# frozen_string_literal: true

require "spec_helper"
require "datadog/open_feature/flag_evaluation/writer"

RSpec.describe Datadog::OpenFeature::FlagEvaluation::Writer do
  # A first/last_evaluation value above the schema's minimum (Oct 2025).
  let(:realistic_eval_ms) { 1_760_000_000_000 }

  def expect_telemetry_count(telemetry, metric_name, value, tags = {})
    expect(telemetry).to have_received(:inc).with("tracers", metric_name, value, tags: tags)
  end

  # Regression guard: rescue inside until...end (without begin) is a Ruby SyntaxError.
  # If writer.rb fails to parse, the EVP component silently falls back to nil and no
  # events are ever delivered to mock-intake.
  it "loads without SyntaxError" do
    expect { described_class }.not_to raise_error
  end

  describe "#enqueue / background flush integration" do
    let(:transport) { instance_double(Datadog::OpenFeature::Transport::HTTP) }
    let(:logger) { instance_double(Logger, debug: nil) }

    it "enqueues an event and flushes it via transport" do
      allow(transport).to receive(:send_flag_evaluations)
      # Stub the background thread so we control flush timing
      allow_any_instance_of(described_class).to receive(:start_background_thread).and_return(nil)
      writer = described_class.new(transport: transport, logger: logger)

      writer.enqueue(
        flag_key: "my-flag",
        variant: "on",
        allocation_key: "",
        targeting_key: "user-1",
        eval_time_ms: 1_234_567_890_000,
        attrs: {},
      )

      # Flush manually (skip background thread)
      writer.send(:drain_and_flush)

      expect(transport).to have_received(:send_flag_evaluations) do |payload|
        expect(payload["flagEvaluations"]).not_to be_empty
        expect(payload["flagEvaluations"].first["flag"]["key"]).to eq("my-flag")
      end
    end
  end

  describe "#stop drains and flushes a sleeping worker" do
    let(:transport) { instance_double(Datadog::OpenFeature::Transport::HTTP) }
    let(:logger) { instance_double(Logger, debug: nil) }

    it "enqueues, then stop() flushes the queued event to the transport before joining" do
      received = Queue.new
      allow(transport).to receive(:send_flag_evaluations) do |payload|
        received << payload if payload["flagEvaluations"]&.any?
      end

      writer = described_class.new(transport: transport, logger: logger)

      # Worker is now alive and waiting on the condition variable (effectively sleeping).
      writer.enqueue(
        flag_key: "shutdown-flag", variant: "on", allocation_key: "",
        targeting_key: "u1", eval_time_ms: 1_000, attrs: {}
      )

      # stop() must wake the sleeping worker immediately, drain, and final-flush (no 10s wait).
      start = Datadog::Core::Utils::Time.get_time
      writer.stop
      elapsed = Datadog::Core::Utils::Time.get_time - start

      payload = try_wait_until(seconds: 1) { received.pop(true) unless received.empty? }
      expect(payload["flagEvaluations"].first["flag"]["key"]).to eq("shutdown-flag")
      # Shutdown returned well under the 10s flush interval (proves the wait was interrupted).
      expect(elapsed).to be < 9
    end

    it "flushes an event enqueued after stop starts but before the final drain" do
      drain_started = Queue.new
      release_drain = Queue.new
      received = Queue.new
      allow(transport).to receive(:send_flag_evaluations) do |payload|
        received << payload if payload["flagEvaluations"]&.any?
      end

      writer = described_class.new(transport: transport, logger: logger)
      drain_calls = 0
      allow(writer).to receive(:drain_queue).and_wrap_original do |method, *args, **kwargs|
        drain_calls += 1
        if drain_calls == 1
          drain_started << true
          release_drain.pop
        end
        kwargs.empty? ? method.call(*args) : method.call(*args, **kwargs)
      end

      stop_thread = Thread.new { writer.stop }
      drain_started.pop

      writer.enqueue(
        flag_key: "late-shutdown-flag", variant: "on", allocation_key: "",
        targeting_key: "u2", eval_time_ms: 2_000, attrs: {}
      )
      release_drain << true
      stop_thread.join

      payload = try_wait_until(seconds: 1) { received.pop(true) unless received.empty? }
      expect(payload["flagEvaluations"].first["flag"]["key"]).to eq("late-shutdown-flag")
    ensure
      release_drain << true if release_drain&.empty?
      stop_thread&.join
      writer&.stop
    end

    it "terminates the worker when graceful shutdown times out" do
      allow_any_instance_of(described_class).to receive(:start_background_thread).and_return(nil)
      writer = described_class.new(transport: transport, logger: logger)

      allow(writer).to receive(:join).with(described_class::SHUTDOWN_TIMEOUT_SECONDS).and_return(false)
      expect(writer).to receive(:terminate).and_return(true)

      expect(writer.stop).to be(true)
    end
  end

  describe "#background drain" do
    let(:transport) { instance_double(Datadog::OpenFeature::Transport::HTTP) }
    let(:logger) { instance_double(Logger, debug: nil) }

    it "flushes a bounded drain cycle before the queue is empty" do
      stub_const("#{described_class}::MAX_DRAIN_EVENTS_PER_CYCLE", 2)
      allow_any_instance_of(described_class).to receive(:start_background_thread).and_return(nil)
      allow(transport).to receive(:send_flag_evaluations)
      writer = described_class.new(transport: transport, logger: logger)

      5.times do |i|
        writer.enqueue(
          flag_key: "bounded-drain", variant: "on", allocation_key: "",
          targeting_key: "user-#{i}", eval_time_ms: realistic_eval_ms + i, attrs: {"bucket" => i}
        )
      end

      writer.send(:drain_queue)
      expect(writer.instance_variable_get(:@queue).length).to eq(3)

      writer.send(:flush_once)
      expect(transport).to have_received(:send_flag_evaluations) do |payload|
        rows = payload["flagEvaluations"]
        expect(rows.sum { |row| row["evaluation_count"] }).to eq(2)
      end
    ensure
      writer&.stop
    end

    it "accumulates more events than the bounded queue can hold before flushing" do
      stub_const("#{described_class}::QUEUE_SIZE", 8)
      stub_const("#{described_class}::DRAIN_INTERVAL_SECONDS", 0.01)
      stub_const("#{described_class}::FLUSH_INTERVAL_SECONDS", 3600)

      received = Queue.new
      allow(transport).to receive(:send_flag_evaluations) do |payload|
        received << payload if payload["flagEvaluations"]&.any?
      end

      writer = described_class.new(transport: transport, logger: logger)
      writer.instance_variable_set(
        :@aggregator,
        Datadog::OpenFeature::FlagEvaluation::Aggregator.new(global_cap: 100, per_flag_cap: 12, degraded_cap: 10),
      )
      queue = writer.instance_variable_get(:@queue)

      14.times do |i|
        try_wait_until(attempts: 100, backoff: 0.001) { queue.length < described_class::QUEUE_SIZE }
        writer.enqueue(
          flag_key: "natural-degrade", variant: "on", allocation_key: "alloc",
          targeting_key: "user-#{i}", eval_time_ms: realistic_eval_ms + i, attrs: {"bucket" => i}
        )
      end

      writer.stop

      payload = try_wait_until(seconds: 1) { received.pop(true) unless received.empty? }
      rows = payload["flagEvaluations"]
      degraded = rows.find { |row| row["flag"]["key"] == "natural-degrade" && !row.key?("targeting_key") }

      expect(writer.dropped_queue_overflow).to eq(0)
      expect(rows.sum { |row| row["evaluation_count"] }).to eq(14)
      expect(degraded).not_to be_nil
      expect(degraded["evaluation_count"]).to eq(2)
    end
  end

  describe "prefork worker restart" do
    let(:logger) { Logger.new(File::NULL) }
    let(:transport_class) do
      Class.new do
        attr_reader :payloads

        def initialize
          @payloads = []
        end

        def send_flag_evaluations(payload)
          @payloads << payload
        end
      end
    end

    it "restarts the background worker in the child and flushes child evaluations" do
      skip "Fork not supported on current platform" unless Process.respond_to?(:fork)

      stub_const("#{described_class}::DRAIN_INTERVAL_SECONDS", 0.01)

      transport = transport_class.new
      writer = described_class.new(transport: transport, logger: logger)
      try_wait_until { writer.running? }

      expect_in_fork do
        expect(writer).to be_forked
        expect(writer).not_to be_running

        writer.enqueue(
          flag_key: "prefork-flag", variant: "on", allocation_key: "alloc",
          targeting_key: "prefork-user", eval_time_ms: realistic_eval_ms, attrs: {"worker" => "child"}
        )
        writer.stop

        rows = transport.payloads.flat_map { |payload| payload["flagEvaluations"] }
        expect(rows).to contain_exactly(
          include(
            "flag" => {"key" => "prefork-flag"},
            "targeting_key" => "prefork-user",
            "evaluation_count" => 1,
          ),
        )
      end
    ensure
      writer&.stop
    end

    it "drops inherited parent buffers before the child worker restarts" do
      allow_any_instance_of(described_class).to receive(:start_background_thread).and_return(nil)
      transport = transport_class.new
      writer = described_class.new(transport: transport, logger: logger)

      writer.enqueue(
        flag_key: "parent-flag", variant: "on", allocation_key: "alloc",
        targeting_key: "parent-user", eval_time_ms: realistic_eval_ms, attrs: {"worker" => "parent"}
      )
      writer.instance_variable_set(:@dropped_queue_overflow, 3)

      writer.send(:after_fork)
      writer.enqueue(
        flag_key: "child-flag", variant: "on", allocation_key: "alloc",
        targeting_key: "child-user", eval_time_ms: realistic_eval_ms, attrs: {"worker" => "child"}
      )
      writer.send(:drain_and_flush)

      rows = transport.payloads.flat_map { |payload| payload["flagEvaluations"] }
      expect(rows).to contain_exactly(include("flag" => {"key" => "child-flag"}))
      expect(writer.dropped_queue_overflow).to eq(0)
    end
  end

  # Backpressure must be OBSERVABLE. When the hand-off queue overflows, enqueue increments an
  # observable counter that is emitted (logged) on the next flush — not silently dropped.
  describe "#enqueue queue-overflow backpressure" do
    let(:transport) { instance_double(Datadog::OpenFeature::Transport::HTTP, send_flag_evaluations: nil) }
    let(:logger) { instance_double(Logger, debug: nil) }
    let(:telemetry) { spy("telemetry") }

    it "increments dropped_queue_overflow and emits the count on flush" do
      allow_any_instance_of(described_class).to receive(:start_background_thread).and_return(nil)
      writer = described_class.new(transport: transport, logger: logger, telemetry: telemetry)

      # Fill the queue to capacity, then overflow it.
      capacity = described_class::QUEUE_SIZE
      event = {
        flag_key: "f", variant: "on", allocation_key: "",
        targeting_key: "t", eval_time_ms: 1, attrs: {},
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
      expect_telemetry_count(
        telemetry,
        "flagevaluation.rows.dropped",
        3,
        {reason: "queue_overflow"},
      )
      expect(writer.dropped_queue_overflow).to eq(0)
    end

    it "does not flatten or prune context before buffering" do
      allow_any_instance_of(described_class).to receive(:start_background_thread).and_return(nil)
      writer = described_class.new(transport: transport, logger: logger)
      raw = {"profile" => {"plan" => "pro"}, "oversized" => "x" * 257}
      300.times { |i| raw["z#{format("%03d", i)}"] = "v" }

      expect(Datadog::OpenFeature::FlagEvaluation::Aggregator).not_to receive(:prune_context)
      writer.enqueue(
        flag_key: "f", variant: "on", allocation_key: "",
        targeting_key: "t", eval_time_ms: 1, attrs: raw
      )

      queued = writer.instance_variable_get(:@queue).pop(true)
      expect(queued[:attrs].size).to eq(302)
      expect(queued[:attrs]).to have_key("profile")
      expect(queued[:attrs]).to have_key("oversized")
      expect(queued[:attrs]).not_to have_key("profile.plan")
    end
  end

  describe "emitted payload shape" do
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

    it "emits a full-tier row with variant, allocation, targeting_key, and context" do
      payload = captured_payload do |writer|
        writer.enqueue(
          flag_key: "schema-flag", variant: "on", allocation_key: "alloc-1",
          targeting_key: "user-42",
          eval_time_ms: realistic_eval_ms, attrs: {"env" => "prod", "tier" => "gold"}
        )
      end

      row = payload["flagEvaluations"].first
      # Structural assertions: objects, not bare strings.
      expect(row["variant"]).to eq("key" => "on")
      expect(row["allocation"]).to eq("key" => "alloc-1")
      expect(row["targeting_key"]).to eq("user-42")
      expect(row["context"]).to eq("evaluation" => {"env" => "prod", "tier" => "gold"})
    end

    it "uses flush time for timestamp and evaluation time for first/last bounds" do
      payload = nil
      transport = instance_double(Datadog::OpenFeature::Transport::HTTP)
      allow(transport).to receive(:send_flag_evaluations) { |p| payload = p }
      allow_any_instance_of(described_class).to receive(:start_background_thread).and_return(nil)
      writer = described_class.new(transport: transport, logger: logger)

      writer.enqueue(
        flag_key: "time-flag", variant: "on", allocation_key: "alloc-1",
        targeting_key: "user-42", eval_time_ms: realistic_eval_ms, attrs: {}
      )

      before_flush = (Datadog::Core::Utils::Time.now.to_f * 1000).to_i
      writer.send(:drain_and_flush)
      after_flush = (Datadog::Core::Utils::Time.now.to_f * 1000).to_i

      row = payload["flagEvaluations"].first
      expect(row["timestamp"]).to be_between(before_flush, after_flush)
      expect(row["first_evaluation"]).to eq(realistic_eval_ms)
      expect(row["last_evaluation"]).to eq(realistic_eval_ms)
    end

    it "does not emit flagevaluation telemetry counters for the normal path" do
      telemetry = spy("telemetry")
      transport = instance_double(Datadog::OpenFeature::Transport::HTTP)
      allow(transport).to receive(:send_flag_evaluations)
      allow_any_instance_of(described_class).to receive(:start_background_thread).and_return(nil)
      writer = described_class.new(transport: transport, logger: logger, telemetry: telemetry)

      writer.enqueue(
        flag_key: "normal-flag", variant: "on", allocation_key: "alloc-1",
        targeting_key: "user-42", eval_time_ms: realistic_eval_ms, attrs: {"env" => "prod"}
      )
      writer.send(:drain_and_flush)

      expect(telemetry).not_to have_received(:inc)
    end

    it "emits a degraded-tier row without targeting_key or context" do
      payload = captured_payload do |writer|
        # Force overflow into the degraded tier with a tiny-capped aggregator.
        small = Datadog::OpenFeature::FlagEvaluation::Aggregator.new(global_cap: 1, per_flag_cap: 1, degraded_cap: 10)
        writer.instance_variable_set(:@aggregator, small)
        writer.enqueue(
          flag_key: "deg-flag", variant: "a", allocation_key: "alloc-x",
          targeting_key: "u1", eval_time_ms: realistic_eval_ms, attrs: {"x" => 1}
        )
        writer.enqueue(
          flag_key: "deg-flag", variant: "a", allocation_key: "alloc-x",
          targeting_key: "u2", eval_time_ms: realistic_eval_ms, attrs: {"x" => 2}
        )
      end

      degraded_row = payload["flagEvaluations"].find { |r| !r.key?("targeting_key") && !r.key?("context") }
      expect(degraded_row).not_to be_nil
      expect(degraded_row["variant"]).to eq("key" => "a")
      expect(degraded_row["allocation"]).to eq("key" => "alloc-x")
    end

    it "emits a degraded counter for rows routed to the degraded tier" do
      telemetry = spy("telemetry")
      transport = instance_double(Datadog::OpenFeature::Transport::HTTP)
      allow(transport).to receive(:send_flag_evaluations)
      allow_any_instance_of(described_class).to receive(:start_background_thread).and_return(nil)
      writer = described_class.new(transport: transport, logger: logger, telemetry: telemetry)
      small = Datadog::OpenFeature::FlagEvaluation::Aggregator.new(global_cap: 1, per_flag_cap: 1, degraded_cap: 10)
      writer.instance_variable_set(:@aggregator, small)

      writer.enqueue(
        flag_key: "deg-flag", variant: "a", allocation_key: "alloc-x",
        targeting_key: "u1", eval_time_ms: realistic_eval_ms, attrs: {"x" => 1}
      )
      3.times do |i|
        writer.enqueue(
          flag_key: "deg-flag", variant: "a", allocation_key: "alloc-x",
          targeting_key: "u#{i + 2}", eval_time_ms: realistic_eval_ms + i + 1, attrs: {"x" => i + 2}
        )
      end
      writer.send(:drain_and_flush)

      expect_telemetry_count(
        telemetry,
        "flagevaluation.rows.degraded",
        3,
        {reason: "cardinality_cap"},
      )
    end

    # The emitted context must hold the PRUNED attrs (oversized strings removed, <=256 fields),
    # not the raw attrs. Proven by inspecting the emitted payload, not the aggregator internals.
    it "emits PRUNED context attrs in the payload (oversized strings removed, capped at 256 fields)" do
      raw = {"keep" => "ok", "toobig" => "x" * 257}
      300.times { |i| raw["k#{format("%03d", i)}"] = "v" }

      payload = captured_payload do |writer|
        writer.enqueue(
          flag_key: "prune-flag", variant: "on", allocation_key: "",
          targeting_key: "t", eval_time_ms: realistic_eval_ms, attrs: raw
        )
      end

      emitted = payload["flagEvaluations"].first["context"]["evaluation"]
      expect(emitted.size).to eq(256)              # capped
      expect(emitted).not_to have_key("toobig")    # oversized string removed
      # Deterministic subset = sorted-first 256 keys (so 'k000'..'k253' kept, 'keep'/'k254'+ cut).
      expect(emitted).to have_key("k000")
      expect(emitted).not_to have_key("k299")
    end

    it "emits an enqueue-time snapshot of nested context attrs" do
      raw = {
        "profile" => {"plan" => "pro"},
        "groups" => ["beta"],
        "name" => +"alice",
      }

      payload = captured_payload do |writer|
        writer.enqueue(
          flag_key: "snapshot-flag", variant: "on", allocation_key: "",
          targeting_key: "t", eval_time_ms: realistic_eval_ms, attrs: raw
        )

        raw["profile"]["plan"] = "enterprise"
        raw["groups"][0] = "ga"
        raw["name"].replace("bob")
      end

      emitted = payload["flagEvaluations"].first["context"]["evaluation"]
      expect(emitted).to include(
        "profile.plan" => "pro",
        "groups.0" => "beta",
        "name" => "alice",
      )
    end

    it "emits non-cyclic context attrs when attrs contain cycles" do
      raw = {"keep" => "ok"}
      raw["self"] = raw
      raw["array"] = []
      raw["array"] << raw["array"]

      payload = captured_payload do |writer|
        writer.enqueue(
          flag_key: "cyclic-context-flag", variant: "on", allocation_key: "",
          targeting_key: "t", eval_time_ms: realistic_eval_ms, attrs: raw
        )
      end

      emitted = payload["flagEvaluations"].first["context"]["evaluation"]
      expect(emitted).to include("keep" => "ok")
      expect(emitted.keys.grep(/self|array/)).to be_empty
    end

    it "emits schema-visible error.message when present" do
      payload = captured_payload do |writer|
        writer.enqueue(
          flag_key: "error-flag", variant: nil, allocation_key: "",
          error_message: "flag not found", targeting_key: "user-42",
          eval_time_ms: realistic_eval_ms, attrs: {}
        )
      end

      row = payload["flagEvaluations"].first
      expect(row["runtime_default_used"]).to be(true)
      expect(row["error"]).to eq("message" => "flag not found")
      expect(row).not_to have_key("reason")
    end

    it "emits runtime_default_used when the hook marks a typed default with a variant" do
      payload = captured_payload do |writer|
        writer.enqueue(
          flag_key: "typed-default-flag", variant: "variant-a", allocation_key: "",
          runtime_default: true, targeting_key: "user-42",
          eval_time_ms: realistic_eval_ms, attrs: {}
        )
      end

      row = payload["flagEvaluations"].first
      expect(row["variant"]).to eq("key" => "variant-a")
      expect(row["runtime_default_used"]).to be(true)
    end

    it "does not split aggregates when only stale reason inputs differ" do
      payload = captured_payload do |writer|
        writer.enqueue(
          flag_key: "reasonless-flag", variant: "on", allocation_key: "alloc-1",
          reason: "TARGETING_MATCH", targeting_key: "user-42",
          eval_time_ms: realistic_eval_ms, attrs: {"env" => "prod"}
        )
        writer.enqueue(
          flag_key: "reasonless-flag", variant: "on", allocation_key: "alloc-1",
          reason: "DEFAULT", targeting_key: "user-42",
          eval_time_ms: realistic_eval_ms + 1, attrs: {"env" => "prod"}
        )
      end

      expect(payload["flagEvaluations"].size).to eq(1)
      expect(payload["flagEvaluations"].first["evaluation_count"]).to eq(2)
      expect(payload["flagEvaluations"].first).not_to have_key("reason")
    end
  end

  describe "payload size limit" do
    subject(:writer) { described_class.new(transport: transport, logger: logger, telemetry: telemetry) }

    let(:payloads) { [] }
    let(:logged) { [] }
    let(:transport) { instance_double(Datadog::OpenFeature::Transport::HTTP) }
    let(:logger) { instance_double(Logger) }
    let(:telemetry) { spy("telemetry") }

    before do
      allow_any_instance_of(described_class).to receive(:start_background_thread).and_return(nil)
      allow(transport).to receive(:send_flag_evaluations) { |payload| payloads << payload }
      allow(logger).to receive(:debug) { |&blk| logged << blk.call }
    end

    def encoded_payload_size(payload)
      Datadog::Core::Encoding::JSONEncoder.encode(payload).bytesize
    end

    it "splits aggregate payloads so each request stays under the configured payload limit" do
      stub_const("#{described_class}::PAYLOAD_SIZE_LIMIT_BYTES", 520)

      writer.enqueue(
        flag_key: "flag-a", variant: "on", allocation_key: "alloc",
        targeting_key: "user-a", eval_time_ms: realistic_eval_ms, attrs: {"blob" => "a" * 180}
      )
      writer.enqueue(
        flag_key: "flag-b", variant: "on", allocation_key: "alloc",
        targeting_key: "user-b", eval_time_ms: realistic_eval_ms, attrs: {"blob" => "b" * 180}
      )
      writer.send(:drain_and_flush)

      expect(payloads.size).to be > 1
      expect(payloads).to all(satisfy { |payload| encoded_payload_size(payload) <= described_class::PAYLOAD_SIZE_LIMIT_BYTES })
      expect_telemetry_count(telemetry, "flagevaluation.payload.splits", payloads.size - 1)
    end

    it "degrades a full row before dropping it for the configured payload limit" do
      stub_const("#{described_class}::PAYLOAD_SIZE_LIMIT_BYTES", 350)

      writer.enqueue(
        flag_key: "large", variant: "on", allocation_key: "alloc",
        targeting_key: "user-large", eval_time_ms: realistic_eval_ms, attrs: {"blob" => "x" * 256}
      )
      writer.send(:drain_and_flush)

      expect(payloads).to contain_exactly(satisfy { |payload| encoded_payload_size(payload) <= described_class::PAYLOAD_SIZE_LIMIT_BYTES })
      row = payloads.first["flagEvaluations"].first
      expect(row["flag"]).to eq("key" => "large")
      expect(row).not_to have_key("targeting_key")
      expect(row).not_to have_key("context")
      expect_telemetry_count(
        telemetry,
        "flagevaluation.rows.degraded",
        1,
        {reason: "payload_limit"},
      )
      expect(logged).to be_empty
    end

    it "drops an already-degraded row that still exceeds the configured payload limit" do
      stub_const("#{described_class}::PAYLOAD_SIZE_LIMIT_BYTES", 128)

      writer.enqueue(
        flag_key: "f" * 256, variant: "on", allocation_key: "alloc",
        targeting_key: "", eval_time_ms: realistic_eval_ms, attrs: {}
      )
      writer.send(:drain_and_flush)

      expect(payloads).to be_empty
      expect(logged.join).to include("payload_oversize=1")
      expect_telemetry_count(
        telemetry,
        "flagevaluation.rows.dropped",
        1,
        {reason: "payload_limit"},
      )
    end
  end

  describe "#send_payload_batch" do
    let(:transport) { instance_double(Datadog::OpenFeature::Transport::HTTP) }
    let(:logger) { instance_double(Logger, debug: nil) }

    it "checks non-OK transport responses and returns the response" do
      allow_any_instance_of(described_class).to receive(:start_background_thread).and_return(nil)
      response = double("TransportResponse")
      allow(response).to receive(:ok?).and_return(false)
      allow(transport).to receive(:send_flag_evaluations).and_return(response)
      writer = described_class.new(transport: transport, logger: logger)

      expect(writer.send(:send_payload_batch, [])).to be(response)
      expect(response).to have_received(:ok?)
    end
  end

  # The aggregator's degraded-overflow count must be EMITTED before reset (not reset-without-emit).
  describe "#flush_once emits degraded-overflow drops" do
    let(:transport) { instance_double(Datadog::OpenFeature::Transport::HTTP, send_flag_evaluations: nil) }
    let(:logger) { instance_double(Logger) }
    let(:telemetry) { spy("telemetry") }

    it "logs the degraded_overflow count returned in the aggregator snapshot" do
      allow_any_instance_of(described_class).to receive(:start_background_thread).and_return(nil)
      writer = described_class.new(transport: transport, logger: logger, telemetry: telemetry)

      # Inject an aggregator whose flush reports a degraded-overflow drop.
      fake_aggregator = instance_double(Datadog::OpenFeature::FlagEvaluation::Aggregator)
      allow(fake_aggregator).to receive(:flush_and_reset).and_return(
        {full: {}, degraded: {}, dropped_degraded_overflow: 7},
      )
      writer.instance_variable_set(:@aggregator, fake_aggregator)

      logged = []
      allow(logger).to receive(:debug) { |&blk| logged << blk.call }

      writer.send(:flush_once)

      expect(logged.join).to match(/degraded_overflow=7/)
      expect_telemetry_count(
        telemetry,
        "flagevaluation.rows.dropped",
        7,
        {reason: "degraded_cap"},
      )
    end
  end
end
