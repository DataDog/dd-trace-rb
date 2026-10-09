require "datadog/di/spec_helper"
require "datadog/core/metrics/dogstatsd"
require "datadog/di/metric_emitter"
require "datadog/di"
require "datadog/statsd"

class MetricProbesIntegrationSpecTestClass
  def test_method(value)
    value * 2
  end
end

RSpec.describe "Metric probes integration" do
  di_test

  let(:diagnostics_transport) do
    double(Datadog::DI::Transport::Diagnostics::Transport)
  end

  let(:input_transport) do
    double(Datadog::DI::Transport::Input::Transport)
  end

  let(:fake_statsd) do
    instance_double(Datadog::Statsd, host: "127.0.0.1", port: 8125)
  end

  let(:installed_version) { Gem::Version.new("5.7.1") }

  let(:diagnostics_batches) { [] }

  let(:input_batches) { [] }

  before do
    # No agent implements the debugger endpoints in CI, so all transport
    # requests are captured instead of reaching the network.
    allow(Datadog::DI::Transport::HTTP).to receive(:diagnostics).and_return(diagnostics_transport)
    allow(Datadog::DI::Transport::HTTP).to receive(:input).and_return(input_transport)
    allow(diagnostics_transport).to receive(:send_diagnostics) { |batch| diagnostics_batches << batch }
    allow(input_transport).to receive(:send_input) { |batch, *_args| input_batches << batch }

    allow(Datadog::Core::Metrics::Dogstatsd).to receive(:installed_version).and_return(installed_version)
    # Only the DI emitter's client carries the product namespace; the core
    # metrics client that the global test teardown rebuilds must keep
    # constructing its own real statsd client, or its double leaks into
    # the next example.
    allow(Datadog::Statsd).to receive(:new).and_wrap_original do |method, *args, **kwargs|
      if kwargs[:namespace] == Datadog::DI::MetricEmitter::NAMESPACE
        fake_statsd
      else
        method.call(*args, **kwargs)
      end
    end
    allow(fake_statsd).to receive(:count)
    allow(fake_statsd).to receive(:gauge)
  end

  after do
    component.shutdown!
  end

  let(:settings) do
    Datadog::Core::Configuration::Settings.new.tap do |settings|
      settings.remote.enabled = true
      settings.dynamic_instrumentation.enabled = true
      settings.dynamic_instrumentation.internal.development = true
      # Propagation is off so the error paths under test report their
      # error statuses instead of re-raising past the reporting code.
      settings.dynamic_instrumentation.internal.propagate_all_exceptions = false
    end
  end

  let(:agent_settings) do
    instance_double_agent_settings
  end

  let(:logger) { logger_allowing_debug }

  let(:component) do
    Datadog::DI::Component.build(settings, agent_settings, logger).tap do |component|
      if component.nil?
        raise "Component failed to create - unsuitable environment? Check log entries"
      end
      component.start!
    end
  end

  let(:probe_manager) do
    component.probe_manager
  end

  let(:probe_spec) do
    {"id" => "metric-integration-probe",
     "version" => 0,
     "type" => "METRIC_PROBE",
     "kind" => "COUNT",
     "metricName" => "integration.metric",
     "where" => {"typeName" => "MetricProbesIntegrationSpecTestClass", "methodName" => "test_method"},
     "evaluateAt" => "EXIT",
     "tags" => ["env:prod"],
     "value" => {"dsl" => "@return", "json" => {"ref" => "@return"}}}
  end

  context "with the metric emitter available" do
    it "installs the probe from the payload, emits on the statsd client, and reports the full status sequence" do
      allow(component).to receive(:telemetry)

      probe = component.parse_probe_spec_and_notify(probe_spec)
      probe_manager.add_probe(probe)

      expect(MetricProbesIntegrationSpecTestClass.new.test_method(21)).to eq 42

      expect(fake_statsd).to have_received(:count).with(
        "integration.metric", 42, tags: ["env:prod", "debugger.probeid:metric-integration-probe"],
      )

      component.probe_notifier_worker.flush

      statuses = diagnostics_batches.flatten.map { |payload|
        payload.fetch(:debugger).fetch(:diagnostics).fetch(:status)
      }
      expect(statuses).to eq ["RECEIVED", "INSTALLED", "EMITTING"]
    end

    it "emits with the metric prefix and kind of the probe" do
      probe = component.parse_probe_spec_and_notify(probe_spec)
      probe_manager.add_probe(probe)

      expect(MetricProbesIntegrationSpecTestClass.new.test_method(21)).to eq 42

      expect(Datadog::Statsd).to have_received(:new).with(
        Datadog::Core::Metrics::Dogstatsd.default_hostname,
        Datadog::Core::Metrics::Dogstatsd.default_port,
        namespace: "dynamic.instrumentation.metric.probe",
        single_thread: true,
      )
    end
  end

  context "with the metric emitter unavailable" do
    let(:installed_version) { nil }

    it "rejects the probe at install with an ERROR status naming the dependency" do
      allow(component).to receive(:telemetry)

      probe = component.parse_probe_spec_and_notify(probe_spec)

      expect do
        probe_manager.add_probe(probe)
      end.to raise_error(Datadog::DI::Error::MetricEmissionUnavailable, /dogstatsd-ruby >= 3\.3\.0/)

      component.probe_notifier_worker.flush

      error_payloads = diagnostics_batches.flatten.select { |payload|
        payload.dig(:debugger, :diagnostics, :status) == "ERROR"
      }
      expect(error_payloads).to_not be_empty
      expect(error_payloads.first.dig(:debugger, :diagnostics, :exception, :message)).to match(/dogstatsd-ruby >= 3\.3\.0/)

      expect(probe_manager.probe_repository.find_failed(probe.id)).to match(/MetricEmissionUnavailable/)
    end
  end

  context "driven through the remote configuration receiver" do
    let(:repository) do
      Datadog::Core::Remote::Configuration::Repository.new
    end

    let(:transaction) do
      DIHelpers::TestRemoteConfigGenerator.new(
        "datadog/2/LIVE_DEBUGGING/metric-integration-probe/hash" => probe_spec,
      ).insert_transaction(repository)
    end

    let(:receiver) do
      Datadog::DI::Remote.receivers(component.telemetry)[0]
    end

    before do
      allow(Datadog::DI).to receive(:component).and_return(component)
      # Force the transaction let so the probe config is inserted into the
      # repository before the receiver consumes it.
      transaction
    end

    context "when the emitter is available" do
      it "installs the probe and acknowledges the content" do
        content = repository.contents.find { |content| content.path.config_id == "metric-integration-probe" }
        expect(content).to_not be nil

        receiver.call(repository, transaction)

        expect(content.apply_state).to be(
          Datadog::Core::Remote::Configuration::Content::ApplyState::ACKNOWLEDGED,
        )
        expect(content.apply_error).to be nil
        expect(MetricProbesIntegrationSpecTestClass.new.test_method(21)).to eq 42

        expect(fake_statsd).to have_received(:count).with(
          "integration.metric", 42, tags: ["env:prod", "debugger.probeid:metric-integration-probe"],
        )

        probe_manager.remove_probe("metric-integration-probe")
      end
    end

    context "when the emitter is unavailable" do
      let(:installed_version) { nil }

      it "marks the remote config content errored without raising" do
        content = repository.contents.find { |content| content.path.config_id == "metric-integration-probe" }
        expect(content).to_not be nil

        expect do
          receiver.call(repository, transaction)
        end.not_to raise_error

        expect(content.apply_state).to be(
          Datadog::Core::Remote::Configuration::Content::ApplyState::ERROR,
        )
        expect(content.apply_error).to match(/MetricEmissionUnavailable/)

        component.probe_notifier_worker.flush

        statuses = diagnostics_batches.flatten.map { |payload|
          payload.dig(:debugger, :diagnostics, :status)
        }
        expect(statuses).to include("RECEIVED", "ERROR")
      end
    end
  end

  context "line metric probe against a loaded fixture" do
    before do
      Datadog::DI.activate_tracking!
      load File.join(File.dirname(__FILE__), "..", "hook_line_load.rb")
    end

    after do
      Datadog::DI.deactivate_tracking!
    end

    let(:line_probe_spec) do
      {"id" => "metric-line-integration-probe",
       "version" => 0,
       "type" => "METRIC_PROBE",
       "kind" => "GAUGE",
       "metricName" => "integration.line.metric",
       "where" => {"sourceFile" => "hook_line_load.rb", "lines" => [30]},
       "value" => {"dsl" => "local", "json" => {"ref" => "local"}}}
    end

    it "emits the evaluated local at the line" do
      probe = component.parse_probe_spec_and_notify(line_probe_spec)
      probe_manager.add_probe(probe)

      expect(HookLineLoadTestClass.new.test_method_with_local).to eq 42

      expect(fake_statsd).to have_received(:gauge).with(
        "integration.line.metric", 42, tags: ["debugger.probeid:metric-line-integration-probe"],
      )
    end
  end

  context "evaluation errors" do
    let(:probe_spec) do
      super().merge("value" => {"dsl" => "len(@return)", "json" => {"len" => {"ref" => "@return"}}})
    end

    it "reports the failing expression in an evaluation errors payload, rate limited" do
      allow(component).to receive(:telemetry)

      probe = component.parse_probe_spec_and_notify(probe_spec)
      probe_manager.add_probe(probe)

      expect(MetricProbesIntegrationSpecTestClass.new.test_method(21)).to eq 42
      expect(MetricProbesIntegrationSpecTestClass.new.test_method(21)).to eq 42

      component.probe_notifier_worker.flush

      evaluation_errors = input_batches.flatten.filter_map { |payload|
        payload.dig(:debugger, :snapshot, :evaluationErrors)
      }.flatten
      expect(evaluation_errors.length).to eq 1
      expect(evaluation_errors.first.fetch(:expr)).to eq "len(@return)"
      expect(evaluation_errors.first.fetch(:message)).to match(/Unsupported type for length/)
    end
  end
end
