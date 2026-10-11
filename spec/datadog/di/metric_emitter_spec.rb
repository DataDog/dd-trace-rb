require "datadog/di/spec_helper"
require "datadog/statsd"
require "datadog/di/metric_emitter"
require "datadog/di/probe"

RSpec.describe Datadog::DI::MetricEmitter do
  di_test

  let(:logger) { instance_double(Datadog::DI::Logger).as_null_object }
  let(:telemetry) { instance_double(Datadog::Core::Telemetry::Component).as_null_object }
  let(:installed_version) { Gem::Version.new("5.7.1") }
  let(:statsd) { instance_double(Datadog::Statsd, host: "127.0.0.1", port: 8125) }

  before do
    allow(Datadog::Core::Metrics::Dogstatsd).to receive(:installed_version).and_return(installed_version)
    allow(Datadog::Statsd).to receive(:new).and_return(statsd)
  end

  let(:emitter) { described_class.new(logger, telemetry: telemetry) }

  let(:probe) do
    Datadog::DI::Probe.new(
      id: "probe-42", type: :metric,
      type_name: "Foo", method_name: "bar",
      metric_kind: :count, metric_name: "test.metric",
      tags: ["env:prod"],
    )
  end

  describe "#initialize" do
    context "with a compatible dogstatsd-ruby installed" do
      it "is available and builds the statsd client" do
        expect(emitter.available?).to be true
        expect(emitter.statsd).to be statsd
      end

      it "creates the client with the product namespace" do
        emitter

        expect(Datadog::Statsd).to have_received(:new).with(
          Datadog::Core::Metrics::Dogstatsd.default_hostname,
          Datadog::Core::Metrics::Dogstatsd.default_port,
          namespace: "dynamic.instrumentation.metric.probe",
          single_thread: true,
        )
      end

      it "logs the dogstatsd version and endpoint at debug" do
        strict_logger = instance_double(Datadog::DI::Logger)
        allow(strict_logger).to receive(:debug)
        allow(strict_logger).to receive(:warn)

        described_class.new(strict_logger, telemetry: telemetry)

        expect(strict_logger).to have_received(:debug) do |&block|
          expect(block.call).to match(/di: metric probe emitter using dogstatsd-ruby 5\.7\.1 at 127\.0\.0\.1:8125/)
        end
      end
    end

    context "with an old dogstatsd-ruby installed" do
      let(:installed_version) { Gem::Version.new("3.2.9") }

      it "is unavailable and warns naming the dependency" do
        strict_logger = instance_double(Datadog::DI::Logger)
        warn_messages = []
        allow(strict_logger).to receive(:debug)
        allow(strict_logger).to receive(:warn) { |message| warn_messages << message }

        emitter = described_class.new(strict_logger, telemetry: telemetry)

        expect(emitter.available?).to be false
        expect(warn_messages).to include(a_string_matching(/dogstatsd-ruby >= 3\.3\.0 \(excluding 5\.0\.x, 5\.1\.x, 5\.2\.x\) is required/))
      end

      it "does not create the statsd client" do
        expect(Datadog::Statsd).to_not receive(:new)

        expect(emitter.statsd).to be nil
      end
    end

    context "with an incompatible dogstatsd-ruby installed" do
      let(:installed_version) { Gem::Version.new("5.1.0") }

      it "is unavailable" do
        expect(emitter.available?).to be false
      end
    end

    context "without dogstatsd-ruby installed" do
      let(:installed_version) { nil }

      it "is unavailable" do
        expect(emitter.available?).to be false
      end
    end

    context "when creating the statsd client fails" do
      before do
        allow(Datadog::Statsd).to receive(:new).and_raise(StandardError, "socket setup failed")
      end

      it "is unavailable and warns naming the failure" do
        strict_logger = instance_double(Datadog::DI::Logger)
        warn_messages = []
        allow(strict_logger).to receive(:debug)
        allow(strict_logger).to receive(:warn) { |message| warn_messages << message }

        emitter = described_class.new(strict_logger, telemetry: telemetry)

        expect(emitter.available?).to be false
        expect(warn_messages).to include(a_string_matching(/failed to create the dogstatsd client: StandardError: socket setup failed/))
      end

      it "reports the failure to telemetry" do
        emitter

        expect(telemetry).to have_received(:report).with(
          a_kind_of(StandardError),
          description: "Failed to create the dogstatsd client",
        )
      end
    end
  end

  describe "#emit" do
    before do
      allow(statsd).to receive(:count)
      allow(statsd).to receive(:gauge)
      allow(statsd).to receive(:histogram)
      allow(statsd).to receive(:distribution)
    end

    [
      [:count, :count],
      [:gauge, :gauge],
      [:histogram, :histogram],
      [:distribution, :distribution],
    ].each do |metric_kind, statsd_method|
      context "metric kind #{metric_kind}" do
        let(:probe) do
          Datadog::DI::Probe.new(
            id: "probe-42", type: :metric,
            type_name: "Foo", method_name: "bar",
            metric_kind: metric_kind, metric_name: "test.metric",
            tags: ["env:prod"],
          )
        end

        it "submits the value via the matching statsd method" do
          emitter.emit(probe, 42)

          expect(statsd).to have_received(statsd_method).with(
            "test.metric", 42, tags: ["env:prod", "debugger.probeid:probe-42"],
          )
        end
      end
    end

    it "returns true" do
      expect(emitter.emit(probe, 1)).to be true
    end

    it "adds only the probe id tag when the probe has no tags" do
      no_tags_probe = Datadog::DI::Probe.new(
        id: "probe-42", type: :metric,
        type_name: "Foo", method_name: "bar",
        metric_kind: :count, metric_name: "test.metric",
      )

      emitter.emit(no_tags_probe, 1)

      expect(statsd).to have_received(:count).with(
        "test.metric", 1, tags: ["debugger.probeid:probe-42"],
      )
    end

    it "timestamps the last emission" do
      expect(emitter.last_emitted_at).to be nil

      emitter.emit(probe, 1)

      expect(emitter.last_emitted_at).to be_a(Time)
    end

    it "logs the emission at trace level with the prefixed metric name" do
      strict_logger = instance_double(Datadog::DI::Logger)
      allow(strict_logger).to receive(:debug)
      allow(strict_logger).to receive(:warn)
      allow(strict_logger).to receive(:trace)

      emitter = described_class.new(strict_logger, telemetry: telemetry)
      emitter.emit(probe, 1)

      expect(strict_logger).to have_received(:trace) do |&block|
        expect(block.call).to eq(
          "di: emitted COUNT metric dynamic.instrumentation.metric.probe.test.metric for probe probe-42 (value=1)",
        )
      end
    end

    context "when the statsd client raises" do
      before do
        allow(statsd).to receive(:count).and_raise(StandardError, "datagram failed")
      end

      it "returns false" do
        expect(emitter.emit(probe, 1)).to be false
      end

      it "logs the failure at debug with the exception and first frame" do
        strict_logger = instance_double(Datadog::DI::Logger)
        debug_messages = []
        allow(strict_logger).to receive(:trace)
        allow(strict_logger).to receive(:warn)
        allow(strict_logger).to receive(:debug) { |&block| debug_messages << block.call }

        emitter = described_class.new(strict_logger, telemetry: telemetry)
        emitter.emit(probe, 1)

        expect(debug_messages).to include(a_string_matching(/di: metric submission failed for probe probe-42: StandardError: datagram failed/))
      end

      it "reports the failure to telemetry" do
        emitter.emit(probe, 1)

        expect(telemetry).to have_received(:report).with(
          a_kind_of(StandardError),
          description: "Metric submission failed",
        )
      end

      it "does not timestamp the last emission" do
        emitter.emit(probe, 1)

        expect(emitter.last_emitted_at).to be nil
      end
    end

    context "when the emitter is closed" do
      before do
        allow(statsd).to receive(:close)
        emitter.close
      end

      it "returns false without submitting" do
        expect(emitter.emit(probe, 1)).to be false

        expect(statsd).to_not have_received(:count)
      end
    end
  end

  describe "#close" do
    before do
      allow(statsd).to receive(:close)
    end

    it "closes the statsd client" do
      emitter.close

      expect(statsd).to have_received(:close)
    end

    it "logs the close at trace level" do
      strict_logger = instance_double(Datadog::DI::Logger)
      trace_messages = []
      allow(strict_logger).to receive(:debug)
      allow(strict_logger).to receive(:warn)
      allow(strict_logger).to receive(:trace) { |&block| trace_messages << block.call }

      described_class.new(strict_logger, telemetry: telemetry).close

      expect(trace_messages).to include("di: metric emitter closed")
    end
  end
end
