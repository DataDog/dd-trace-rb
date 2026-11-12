require "datadog/profiling/spec_helper"

RSpec.describe Datadog::Profiling::Miteruby::VirelSerializer do
  subject(:serializer) { described_class.new }

  let(:worker_class) { Datadog::Profiling::Collectors::CpuAndWallTimeWorker }
  let(:worker) do
    worker_class.new(
      miteruby_enabled: true,
      thread_context_collector: nil,
      gc_profiling_enabled: false,
      no_signals_workaround_enabled: true,
      dynamic_sampling_rate_overhead_target_percentage: 2.0,
      allocation_profiling_enabled: false,
      allocation_counting_enabled: false,
      gvl_profiling_enabled: false,
      sighandler_sampling_enabled: false,
      cpu_sampling_interval_ms: 10,
      waiting_for_gvl_threshold_ns: 10_000_000,
    )
  end

  before do
    skip_if_profiling_not_supported
    allow(worker).to receive(:create_miteruby_consumer)
    worker.start
    worker.wait_until_running
    worker.stop
    consume_samples
    serializer.prepare_serialize.serialize!
  end

  after { worker.stop }

  def consume_samples
    consumer = Thread.new { worker_class._native_miteruby_consumer_consume_loop }
    loop_until do
      worker_class::Testing._native_miteruby_wake_reader
      Thread.pass
      worker_class::Testing._native_miteruby_raw_events_queue_empty?
    end
  ensure
    consumer&.kill&.join
  end

  def publish_samples
    [100, 250, 300].each do |cpu|
      expect(worker_class::Testing._native_miteruby_sample_event_publish_testing(Thread.current, cpu)).to be true
    end
    consume_samples
  end

  it "returns a finalized, uncompressed recording with matching timestamps and statistics" do
    publish_samples
    expect(serializer.prepare_serialize).to equal(serializer)
    start, finish, recording, stats = serializer.serialize
    bytes = recording.bytes

    expect(recording.format).to eq(:virel)
    expect(bytes.encoding).to eq(Encoding::BINARY)
    expect(bytes).to be_frozen
    expect(bytes.byteslice(0, 4)).to eq("VIRL")
    expect(bytes.byteslice(4, 4).unpack("n2")).to eq([0, 1])
    expect(bytes.byteslice(8, 8).unpack1("Q>")).to eq(bytes.bytesize)
    expect(bytes.byteslice(32, 8).unpack1("Q>")).to eq((start.to_r * 1_000_000_000).to_i)
    expect(bytes.byteslice(40, 8).unpack1("Q>")).to eq(((finish.to_r - start.to_r) * 1_000_000_000).to_i)
    expect(bytes.byteslice(64, 4).bytes).to eq([0, 0, 128, 2])
    expect(stats).to eq(samples: 3, stacks: 1, bytes: bytes.bytesize)
    expect(serializer.stats).to eq(stats)
    expect(bytes).to include(__FILE__, "#publish_samples")
  end

  it "requires a new preparation after consuming the result" do
    expect { serializer.serialize! }.to raise_error(RuntimeError, /must be prepared/)
    serializer.prepare_serialize.serialize!
    expect { serializer.serialize! }.to raise_error(RuntimeError, /must be prepared/)
  end

  it "preserves independent recording bytes across reuse and compaction" do
    publish_samples
    serializer.prepare_serialize
    GC.start
    GC.verify_compaction_references if GC.respond_to?(:verify_compaction_references)
    recording = serializer.serialize!
    original = recording.bytes.dup
    serializer.prepare_serialize.serialize!

    expect(recording.bytes).to eq(original)
    expect(serializer.stats[:samples]).to eq(0)
  end

  it "resets the writer identity and pending result after a fork reset" do
    first = serializer.prepare_serialize.serialize!.bytes.byteslice(68, 8)
    serializer.prepare_serialize
    expect(serializer.reset_after_fork).to be true
    expect { serializer.serialize! }.to raise_error(RuntimeError, /must be prepared/)
    second = serializer.prepare_serialize.serialize!.bytes.byteslice(68, 8)

    expect(second).to_not eq(first)
    expect(second.unpack1("Q>")).to be > 0
  end

  it "leaves the existing pprof backend usable after a Virel drain" do
    publish_samples
    serializer.prepare_serialize.serialize!
    publish_samples
    samples = samples_from_pprof(worker.prepare_serialize.serialize!)

    expect(samples.size).to eq(3)
    expect(samples.map { |sample| sample.values[:"cpu-time"] }).to eq([0, 150, 50])
  end
end
