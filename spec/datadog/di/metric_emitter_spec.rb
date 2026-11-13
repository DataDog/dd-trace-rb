require "datadog/di/spec_helper"
require "datadog/statsd"
require "datadog/di/metric_emitter"
require "datadog/di/probe"

RSpec.describe Datadog::DI::MetricEmitter do
  di_test

  let(:logger) { instance_double(Datadog::DI::Logger).as_null_object }
  let(:telemetry) { instance_double(Datadog::Core::Telemetry::Component).as_null_object }
  let(:statsd) { instance_double(Datadog::Statsd, count: nil, gauge: nil, histogram: nil, distribution: nil, flush: nil) }

  subject(:emitter) { described_class.new(logger, telemetry: telemetry, statsd: statsd) }

  def metric_probe(kind, id: "probe-#{kind}", tags: ["env:prod"])
    Datadog::DI::Probe.new(
      id: id, type: :metric,
      type_name: "Foo", method_name: "bar",
      metric_kind: kind, metric_name: "test.metric",
      tags: tags,
    )
  end

  let(:probe) { metric_probe(:count, id: "probe-42") }
  let(:metric_name) { "dynamic.instrumentation.metric.probe.test.metric" }

  describe "#initialize" do
    context "with a client" do
      before do
        allow(Datadog::Core::Metrics::Dogstatsd).to receive(:installed_version).and_return(Gem::Version.new("5.7.1"))
      end

      it "logs the dogstatsd-ruby version at debug" do
        expect(logger).to receive(:debug) do |&block|
          expect(block.call).to eq("di: metric probe emitter using dogstatsd-ruby 5.7.1")
        end

        emitter
      end
    end

    context "without a client" do
      let(:statsd) { nil }

      it "logs the unavailability reason at debug" do
        expect(logger).to receive(:debug) do |&block|
          expect(block.call).to eq(
            "di: metric probes are unavailable: dogstatsd-ruby >= 3.3.0 (excluding 5.0.x, 5.1.x, 5.2.x) " \
              "is required; install or upgrade the gem in the application",
          )
        end

        emitter
      end
    end
  end

  describe "#available? and #unavailable_reason" do
    context "with a client" do
      it "is available with no reason" do
        expect(emitter.available?).to be true
        expect(emitter.unavailable_reason).to be nil
      end
    end

    context "without a client" do
      let(:statsd) { nil }

      it "is unavailable and names the dependency" do
        expect(emitter.available?).to be false
        expect(emitter.unavailable_reason).to eq(described_class::DEPENDENCY_REQUIRED_REASON)
      end
    end
  end

  describe "#record" do
    it "makes no client call" do
      expect(emitter.record(probe, 1)).to be true

      expect(statsd).to_not have_received(:count)
      expect(statsd).to_not have_received(:flush)
    end

    it "makes the point pending" do
      expect { emitter.record(probe, 1) }.to change { emitter.pending? }.from(false).to(true)
    end

    context "when the emitter is closed" do
      before { emitter.close }

      it "records nothing" do
        expect(emitter.record(probe, 1)).to be false
        expect(emitter.pending?).to be false
      end
    end

    context "without a client" do
      let(:statsd) { nil }

      it "records nothing" do
        expect(emitter.record(probe, 1)).to be false
        expect(emitter.pending?).to be false
      end
    end

    context "with HISTOGRAM samples beyond the cap" do
      let(:probe) { metric_probe(:histogram) }

      before { stub_const("#{described_class}::MAX_PENDING_SAMPLES", 2) }

      it "drops the samples over the cap and logs the count at the next flush" do
        expect(emitter.record(probe, 1)).to be true
        expect(emitter.record(probe, 2)).to be true
        expect(emitter.record(probe, 3)).to be false
        expect(emitter.record(probe, 4)).to be false

        expect(logger).to receive(:debug) do |&block|
          expect(block.call).to eq("di: dropped 2 HISTOGRAM sample(s) for probe probe-histogram: 2 samples were pending")
        end
        emitter.flush

        expect(statsd).to have_received(:histogram).twice
      end
    end

    context "with an unknown metric kind" do
      it "raises an internal error" do
        allow(probe).to receive(:metric_kind).and_return(:summary)

        expect { emitter.record(probe, 1) }.to raise_error(
          Datadog::DI::Error::InternalError, "unknown metric kind :summary of probe probe-42",
        )
      end
    end
  end

  describe "#flush" do
    it "submits nothing and returns false without pending points" do
      expect(emitter.flush).to be false

      expect(statsd).to_not have_received(:count)
      expect(statsd).to_not have_received(:flush)
      expect(emitter.last_emitted_at).to be nil
    end

    it "submits the sum of the recorded COUNT values" do
      emitter.record(probe, 1)
      emitter.record(probe, 2.5)

      expect(emitter.flush).to be true

      expect(statsd).to have_received(:count).with(metric_name, 3.5, tags: ["env:prod", "debugger.probeid:probe-42"]).once
      expect(statsd).to have_received(:flush).with(no_args).once
      expect(emitter.pending?).to be false
    end

    it "submits the last recorded GAUGE value" do
      gauge_probe = metric_probe(:gauge)
      emitter.record(gauge_probe, 1)
      emitter.record(gauge_probe, 7)

      emitter.flush

      expect(statsd).to have_received(:gauge).with(metric_name, 7, tags: ["env:prod", "debugger.probeid:probe-gauge"]).once
    end

    it "submits each HISTOGRAM and DISTRIBUTION sample" do
      histogram_probe = metric_probe(:histogram)
      distribution_probe = metric_probe(:distribution)
      emitter.record(histogram_probe, 1)
      emitter.record(histogram_probe, 2)
      emitter.record(distribution_probe, 3)

      emitter.flush

      expect(statsd).to have_received(:histogram).with(metric_name, 1, tags: ["env:prod", "debugger.probeid:probe-histogram"])
      expect(statsd).to have_received(:histogram).with(metric_name, 2, tags: ["env:prod", "debugger.probeid:probe-histogram"])
      expect(statsd).to have_received(:distribution).with(metric_name, 3, tags: ["env:prod", "debugger.probeid:probe-distribution"])
    end

    it "passes the probe tags unchanged ahead of the probe id tag" do
      tagged_probe = metric_probe(:count, id: "probe-tags", tags: [" key : value ", "bare", "key:1", "key:2"])
      emitter.record(tagged_probe, 1)

      emitter.flush

      expect(statsd).to have_received(:count).with(
        metric_name, 1, tags: [" key : value ", "bare", "key:1", "key:2", "debugger.probeid:probe-tags"],
      )
    end

    it "sets last_emitted_at" do
      emitter.record(probe, 1)

      expect { emitter.flush }.to change { emitter.last_emitted_at }.from(nil).to(an_instance_of(Time))
    end

    context "with a client that defines no flush" do
      let(:statsd) { double("dogstatsd-ruby 4.x client", count: nil) }

      it "submits the points and makes no flush call" do
        emitter.record(probe, 1)

        expect(emitter.flush).to be true
        expect(statsd).to have_received(:count)
      end
    end

    context "when a submission raises" do
      let(:error) { IOError.new("closed stream") }

      before { allow(statsd).to receive(:count).and_raise(error) }

      it "logs and reports the exception and drops the points" do
        emitter.record(probe, 1)

        expect(logger).to receive(:debug) do |&block|
          expect(block.call).to match(/\Adi: metric flush failed: IOError: closed stream \(.+\)\z/)
        end
        expect(emitter.flush).to be false

        expect(telemetry).to have_received(:report).with(error, description: "Metric flush failed")
        expect(emitter.pending?).to be false
        expect(emitter.last_emitted_at).to be nil
      end
    end

    context "without a client" do
      let(:statsd) { nil }

      it { expect(emitter.flush).to be false }
    end
  end

  describe "pending points inherited across a fork" do
    it "are discarded by the forked process" do
      emitter.record(probe, 1)
      allow(Process).to receive(:pid).and_return(Process.pid + 1)

      expect(emitter.pending?).to be false
      expect(emitter.flush).to be false
      expect(statsd).to_not have_received(:count)
    end

    it "leave the points that the forked process records" do
      emitter.record(probe, 1)
      allow(Process).to receive(:pid).and_return(Process.pid + 1)
      emitter.record(probe, 2)

      emitter.flush

      expect(statsd).to have_received(:count).with(metric_name, 2, tags: ["env:prod", "debugger.probeid:probe-42"]).once
    end
  end

  describe "#close" do
    before do
      allow(statsd).to receive(:close)
    end

    it "flushes the pending points and leaves the client open" do
      emitter.record(probe, 1)

      emitter.close

      expect(statsd).to have_received(:count)
      expect(statsd).to have_received(:flush)
      expect(statsd).to_not have_received(:close)
      expect(emitter.closed?).to be true
    end
  end

  describe "#closed?" do
    it { expect(emitter.closed?).to be false }
  end
end
