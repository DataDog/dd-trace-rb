require "datadog/profiling/spec_helper"
require "datadog/profiling/miteruby/libdatadog_recorder"

RSpec.describe Datadog::Profiling::Miteruby::LibdatadogRecorder do
  before { skip_if_profiling_not_supported }

  subject(:recorder) { described_class.new }

  def record_sample(timestamp: 0)
    described_class::Testing._native_record_sample(recorder, [11, 2, 33, 4, 5, 66], timestamp)
  end

  it "records all non-heap metrics and timeline labels" do
    record_sample(timestamp: 123456789)

    sample = samples_from_pprof(recorder.serialize!).fetch(0)
    expect(sample.values).to eq(
      "cpu-time": 11,
      "cpu-samples": 2,
      "wall-time": 33,
      "alloc-samples": 4,
      "alloc-samples-unscaled": 5,
      timeline: 66,
    )
    expect(sample.labels).to eq(end_timestamp_ns: 123456789)
  end

  it "drains samples and uses contiguous time intervals across flushes" do
    record_sample
    first_start, first_finish, first_encoded, first_stats = recorder.serialize
    second_start, second_finish, second_encoded, second_stats = recorder.serialize

    expect(first_start).to be <= first_finish
    expect(second_start).to eq(first_finish)
    expect(second_finish).to be >= second_start
    expect(samples_from_pprof(first_encoded).size).to eq(1)
    expect(samples_from_pprof(second_encoded)).to be_empty
    expect(first_stats).to match(recorded_samples: 1, serialization_time_ns: be >= 0)
    expect(second_stats).to match(recorded_samples: 0, serialization_time_ns: be >= 0)

    profile = decode_profile(first_encoded)
    expect(profile.time_nanos).to eq((first_start.to_r * 1_000_000_000).to_i)
    expect(profile.duration_nanos).to eq(((first_finish.to_r - first_start.to_r) * 1_000_000_000).to_i)

    record_sample
    expect(samples_from_pprof(recorder.serialize!).size).to eq(1)
  end

  it "reports serialization statistics without heap statistics" do
    expect(recorder.stats).to eq(
      serialization_successes: 0,
      serialization_failures: 0,
      serialization_time_ns_min: nil,
      serialization_time_ns_max: nil,
      serialization_time_ns_total: nil,
      serialization_time_ns_avg: nil,
    )

    2.times { recorder.serialize }
    stats = recorder.stats
    expect(stats).to include(serialization_successes: 2, serialization_failures: 0)
    expect(stats[:serialization_time_ns_min]).to be <= stats[:serialization_time_ns_max]
    expect(stats[:serialization_time_ns_avg]).to eq(stats[:serialization_time_ns_total] / 2.0)
  end

  it "clears samples and restarts the interval when reset after fork" do
    record_sample
    previous_finish = recorder.serialize[1]
    record_sample

    expect(recorder.reset_after_fork).to be(true)
    start, _, encoded, stats = recorder.serialize
    expect(start).to be >= previous_finish
    expect(samples_from_pprof(encoded)).to be_empty
    expect(stats[:recorded_samples]).to eq(0)
    record_sample
    expect(samples_from_pprof(recorder.serialize!).size).to eq(1)
  end

  it "rejects profile access during serialization and releases ownership after an interruption" do
    ready = Queue.new
    release = Queue.new
    serializer = Thread.new do
      described_class::Testing._native_with_serialization_ownership(recorder) do
        ready << true
        release.pop
      end
    end

    begin
      ready.pop
      expect { recorder.serialize }.to raise_error(RuntimeError, /being serialized/)
      expect { record_sample }.to raise_error(RuntimeError, /being serialized/)
      expect { recorder.reset_after_fork }.to raise_error(RuntimeError, /being serialized/)
      expect { Datadog::Profiling::Collectors::CpuAndWallTimeWorker._native_miteruby_consumer_prepare_serialize(recorder) }
        .to raise_error(RuntimeError, /being serialized/)
    ensure
      serializer.kill
      serializer.join
    end

    record_sample
    expect(samples_from_pprof(recorder.serialize!).size).to eq(1)
  end

  it "rejects a classic recorder before consuming events" do
    expect do
      Datadog::Profiling::Collectors::CpuAndWallTimeWorker._native_miteruby_consumer_prepare_serialize(
        Datadog::Profiling::StackRecorder.for_testing,
      )
    end.to raise_error(TypeError)
  end

  context "when serialization fails" do
    before { allow(described_class).to receive(:_native_serialize).with(recorder).and_return([:error, "serialization error"]) }

    it "logs the failure and returns nil" do
      expect(Datadog.logger).to receive(:warn).with("Failed to serialize profiling data: serialization error")
      expect(Datadog::Core::Telemetry::Logger).to receive(:error).with("Failed to serialize profiling data (serialization error)")
      expect(recorder.serialize).to be_nil
    end

    it "raises when using serialize!" do
      expect { recorder.serialize! }.to raise_error(RuntimeError, "Failed to serialize profiling data: serialization error")
    end
  end
end
