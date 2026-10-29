require "datadog/profiling/spec_helper"
require "datadog/profiling/miteruby/libdatadog_recorder"
require "open3"

RSpec.describe Datadog::Profiling::Miteruby::LibdatadogRecorder do
  before { skip_if_profiling_not_supported }

  subject(:recorder) { described_class.new }

  def record_sample(timestamp: 0, values: [11, 2, 33, 4, 5, 66], frames: [], labels: [])
    described_class::Testing._native_record_sample(recorder, values, timestamp, frames, labels)
  end

  def decode_raw(encoded)
    output, error, status = Open3.capture3("protoc", "--decode_raw", stdin_data: Zstd.decompress(encoded._native_bytes), binmode: true)
    expect(status.success?).to be(true), error
    output
  end

  def equivalent_profiles
    status, results = described_class._native_serialize(recorder)
    expect(status).to eq(:ok)
    original, custom = results
    expect(custom.values_at(0, 1, 3)).to eq(original.values_at(0, 1, 3))
    decoded = results.map do |result|
      fields = decode_raw(result[2]).split(/(?=^\d)/).group_by { |field| field[/\A\d+/] }
      # Protobuf field order is immaterial; libdatadog also reorders samples during aggregation.
      fields["2"]&.sort!
      fields
    end
    expect(decoded[1]).to eq(decoded[0])
    [original[2], custom[2]]
  end

  describe "dual serialization" do
    it "produces exactly the same decoded empty profile" do
      original, custom = equivalent_profiles
      expect(decode_raw(custom)).to eq(decode_raw(original))
    end

    it "preserves metric values, timestamps, strings, numeric labels, and shared stack frames" do
      frames = [["leaf", "app/例.rb", 42], ["caller", "app/main.rb", 10], ["leaf", "app/例.rb", 43]]
      labels = [["thread name", "worker\0名前", 0, ""], ["allocation size", "", 4096, "bytes"], ["zero", "", 0, "count"]]
      record_sample(frames: frames, labels: labels, timestamp: 123456789)
      record_sample(frames: frames, labels: labels, timestamp: 123456789)
      record_sample(frames: frames.reverse, labels: labels, timestamp: -123, values: [-11, 0, 0, 0, 0, -66])
      record_sample(values: [0, 0, 0, 0, 0, 0])

      original, custom = equivalent_profiles
      expect(samples_from_pprof(custom)).to match_array(samples_from_pprof(original))
      expect(decode_profile(custom).sample.size).to eq(4)
      expect(decode_profile(custom).location.size).to eq(3)
      expect(decode_profile(custom).function.size).to eq(2)
    end

    it "aggregates untimestamped samples with saturating signed values" do
      2.times { record_sample(values: [2**63 - 1, 2, -2**63, 4, 5, 66], labels: [["thread name", "worker", 0, ""]]) }
      record_sample(labels: [["thread name", "main", 0, ""]])

      _, custom = equivalent_profiles
      sample = samples_from_pprof(custom).find { |item| item.labels[:"thread name"] == "worker" }
      expect(sample.values).to include("cpu-time": 2**63 - 1, "wall-time": -2**63, "cpu-samples": 4, timeline: 132)
      expect(decode_profile(custom).sample.size).to eq(2)
    end

    it "owns recorded strings and encoded bytes across garbage collection and subsequent flushes" do
      150.times do |index|
        name = "frame #{index}"
        record_sample(frames: [[name, "example.rb", index]], timestamp: index + 1)
        name.replace("changed after recording")
      end
      original, custom = equivalent_profiles
      expected = decode_raw(original)
      GC.start
      equivalent_profiles
      expect(decode_raw(custom).split(/(?=^\d)/).sort).to eq(expected.split(/(?=^\d)/).sort)
      expect(decode_profile(custom).string_table).to_not include("changed after recording")
    end

    it "clears both profiles after fork" do
      record_sample(labels: [["thread name", "old thread", 0, ""]])
      recorder.reset_after_fork
      _, custom = equivalent_profiles
      expect(decode_profile(custom).sample).to be_empty
      expect(decode_profile(custom).string_table).to_not include("old thread")
      record_sample
      equivalent_profiles
    end

    it "releases serialization ownership and clears both profiles if wrapping the custom bytes raises" do
      record_sample
      allow(Datadog::Profiling::EncodedProfile).to receive(:from_custom).and_raise("wrapping failed")
      expect { recorder.serialize }.to raise_error("wrapping failed")
      expect(recorder.stats).to include(serialization_failures: 1, serialization_successes: 0)
      allow(Datadog::Profiling::EncodedProfile).to receive(:from_custom).and_call_original
      _, custom = equivalent_profiles
      expect(decode_profile(custom).sample).to be_empty
      record_sample
      equivalent_profiles
    end

    it "returns only the libdatadog result from the Ruby wrapper" do
      record_sample
      status, results = described_class._native_serialize(recorder)
      allow(described_class).to receive(:_native_serialize).with(recorder).and_return([status, results])
      expect(recorder.serialize).to equal(results[0])
      expect(recorder.serialize!).to equal(results[0][2])
    end
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
