# frozen_string_literal: true

require "spec_helper"
require "timeout"
require "open_feature/sdk"
require "datadog/open_feature/component"
require "datadog/open_feature/flag_evaluation/writer"
require "datadog/open_feature/hooks/flag_eval_evp_hook"
require "datadog/open_feature/hooks/span_enrichment_hook"

RSpec.describe Datadog::OpenFeature::Component do
  before do
    allow(Datadog::OpenFeature::Transport::HTTP).to receive(:build).and_return(transport)
    allow(Datadog::OpenFeature::Transport::HTTP).to receive(:build_flagevaluations).and_return(transport)
    allow(Datadog::OpenFeature::Exposures::Worker).to receive(:new).and_return(worker)
    allow(Datadog::OpenFeature::Exposures::Reporter).to receive(:new).and_return(reporter)
    # Lifecycle examples explicitly enable and stop the real background thread.
    allow_any_instance_of(Datadog::OpenFeature::FlagEvaluation::Writer)
      .to receive(:start_background_thread).and_return(nil)
  end

  let(:telemetry) { instance_double(Datadog::Core::Telemetry::Component) }
  let(:settings) { Datadog::Core::Configuration::Settings.new }
  let(:agent_settings) { Datadog::Core::Configuration::AgentSettingsResolver.call(settings) }
  let(:logger) { instance_double(Datadog::Core::Logger, debug: nil, debug?: false, warn: nil) }
  let(:transport) { instance_double(Datadog::OpenFeature::Transport::HTTP) }
  let(:worker) { instance_double(Datadog::OpenFeature::Exposures::Worker) }
  let(:reporter) { instance_double(Datadog::OpenFeature::Exposures::Reporter) }
  let(:resolution) do
    Datadog::OpenFeature::Configuration::Source::Resolution.new("agentless", enabled: true)
  end
  let(:on_configuration_change) { instance_double(Proc, call: nil) }

  describe "production event transport ownership" do
    it "constructs both writers with the same agentless selector, scoped to the component" do
      stub_const("Datadog::Core::LIBDATADOG_API_FAILURE", nil)
      settings.feature_flags.enabled = true
      exposure_transports = []
      evaluation_transports = []
      allow(Datadog::OpenFeature::Exposures::Worker).to receive(:new).and_wrap_original do |constructor, **options|
        exposure_transports << options[:transport]
        constructor.call(**options)
      end
      allow(Datadog::OpenFeature::FlagEvaluation::Writer).to receive(:new).and_wrap_original do |constructor, **options|
        evaluation_transports << options[:transport]
        constructor.call(**options)
      end
      components = 2.times.map do
        described_class.build(settings, agent_settings, resolution: resolution,
          on_configuration_change: on_configuration_change, logger: logger, telemetry: telemetry)
      end
      expect(exposure_transports.size).to eq(2)
      expect(evaluation_transports.size).to eq(2)
      expect(exposure_transports.first).to be_a(Datadog::OpenFeature::Transport::Agentless)
      expect(evaluation_transports.first).to equal(exposure_transports.first)
      expect(evaluation_transports.last).to equal(exposure_transports.last)
      expect(exposure_transports.first).not_to equal(exposure_transports.last)
      expect(Datadog::OpenFeature::Transport::HTTP).not_to have_received(:build)
      expect(Datadog::OpenFeature::Transport::HTTP).not_to have_received(:build_flagevaluations)
    ensure
      components&.each(&:shutdown!)
    end
  end

  describe ".build" do
    subject(:component) do
      described_class.build(
        settings,
        agent_settings,
        resolution: resolution,
        on_configuration_change: on_configuration_change,
        logger: logger,
        telemetry: telemetry,
      )
    end

    context "when open_feature is enabled" do
      before { settings.open_feature.enabled = true }

      context "when remote configuration is enabled" do
        before do
          stub_const("Datadog::Core::LIBDATADOG_API_FAILURE", nil)
          settings.remote.enabled = true
        end

        it "returns configured component instance" do
          expect(component).to be_a(described_class)
          expect(component.engine).to be_a(Datadog::OpenFeature::EvaluationEngine)

          expect(Datadog::OpenFeature::Exposures::Reporter).to have_received(:new)
        end

        describe "span enrichment hook gate" do
          context "when span enrichment is disabled (default)" do
            it "does not construct the span enrichment hook" do
              expect(component.span_enrichment_hook).to be_nil
            end

            it "never loads the span enrichment hook (no idle overhead)" do
              expect(Datadog::OpenFeature::Hooks::SpanEnrichmentHook).not_to receive(:new)

              component
            end
          end

          context "when span enrichment is enabled" do
            before do
              settings.open_feature.span_enrichment_enabled = true
            end

            it "constructs the span enrichment hook" do
              expect(component.span_enrichment_hook)
                .to be_a(Datadog::OpenFeature::Hooks::SpanEnrichmentHook)
            end
          end
        end

        context "when libdatadog is unavailable" do
          before { stub_const("Datadog::Core::LIBDATADOG_API_FAILURE", "Failed to load") }

          it "logs warning and returns nil" do
            expect(logger).to receive(:warn).with(/`libdatadog` is not loaded: "Failed to load"/)

            expect(component).to be_nil
          end
        end

        context "when not running on MRI" do
          before { stub_const("RUBY_ENGINE", "jruby") }

          it "logs warning and returns nil" do
            expect(logger).to receive(:warn).with(/MRI is required, but running on "jruby"/)

            expect(component).to be_nil
          end
        end
      end
    end

    context "when open_feature is not enabled" do
      let(:resolution) do
        Datadog::OpenFeature::Configuration::Source::Resolution.new("offline", enabled: false)
      end

      it { expect(component).to be_nil }
    end
  end

  # The EVP killswitch is read through the config registry (settings.open_feature
  # .evaluation_counts_enabled), NOT raw ENV. When disabled, the EVP hook is not created and the
  # OTel hook is unaffected (non-regression).
  # Hooks only exist when the OpenFeature SDK supports them (>= 0.5); skip on the min appraisal.
  describe "EVP killswitch via config registry", skip: !Datadog::OpenFeature::Hooks::FlagEvalEVPHook.available? do
    before do
      settings.open_feature.enabled = true
      settings.remote.enabled = true
      stub_const("Datadog::Core::LIBDATADOG_API_FAILURE", nil)
    end

    subject(:component) { described_class.new(settings, agent_settings, logger: logger, telemetry: telemetry) }

    context "when evaluation_counts_enabled is true (default)" do
      it "creates the EVP hook" do
        expect(component.flag_eval_evp_hook).to be_a(Datadog::OpenFeature::Hooks::FlagEvalEVPHook)
      end

      it "passes telemetry to the EVP writer" do
        expect(Datadog::OpenFeature::FlagEvaluation::Writer).to receive(:new).with(
          transport: transport,
          logger: logger,
          telemetry: telemetry,
        ).and_call_original

        component
      end
    end

    context "when evaluation_counts_enabled is false" do
      before { settings.open_feature.evaluation_counts_enabled = false }

      it "does not create the EVP hook (killswitch), leaving the OTel hook intact" do
        expect(component.flag_eval_evp_hook).to be_nil
        expect(component.flag_eval_metrics_hook).to be_a(Datadog::OpenFeature::Hooks::FlagEvalMetricsHook)
      end
    end
  end

  describe "#debug_logging_hook", skip: !Datadog::OpenFeature::Hooks::DebugLoggingHook.available? do
    before do
      settings.open_feature.evaluation_counts_enabled = false
      stub_const("Datadog::Core::LIBDATADOG_API_FAILURE", nil)
    end

    subject(:component) { described_class.new(settings, agent_settings, logger: logger, telemetry: telemetry) }

    it "is returned while debug logging is enabled" do
      allow(logger).to receive(:debug?).and_return(true)

      expect(component.debug_logging_hook).to be_a(Datadog::OpenFeature::Hooks::DebugLoggingHook)
    end

    it "is withheld while debug logging is disabled" do
      allow(logger).to receive(:debug?).and_return(false)

      expect(component.debug_logging_hook).to be_nil
    end

    it "reuses one hook across evaluations" do
      allow(logger).to receive(:debug?).and_return(true)

      expect(component.debug_logging_hook).to be(component.debug_logging_hook)
    end

    it "withholds an existing hook when debug logging is disabled later" do
      allow(logger).to receive(:debug?).and_return(true)
      hook = component.debug_logging_hook
      allow(logger).to receive(:debug?).and_return(false)

      expect(component.debug_logging_hook).to be_nil

      allow(logger).to receive(:debug?).and_return(true)
      expect(component.debug_logging_hook).to be(hook)
    end

    it "is built once the OpenFeature SDK loads after the component" do
      allow(logger).to receive(:debug?).and_return(true)
      allow(Datadog::OpenFeature::Hooks::DebugLoggingHook).to receive(:available?).and_return(false)
      component

      expect(component.debug_logging_hook).to be_nil

      allow(Datadog::OpenFeature::Hooks::DebugLoggingHook).to receive(:available?).and_return(true)

      expect(component.debug_logging_hook).to be_a(Datadog::OpenFeature::Hooks::DebugLoggingHook)
    end
  end

  describe "raw evaluation data warning" do
    before do
      settings.open_feature.evaluation_counts_enabled = false
      stub_const("Datadog::Core::LIBDATADOG_API_FAILURE", nil)
    end

    subject(:component) do
      described_class.build(
        settings,
        agent_settings,
        resolution: resolution,
        on_configuration_change: on_configuration_change,
        logger: logger,
        telemetry: telemetry,
      )
    end

    let(:raw_data_warning) { Datadog::OpenFeature::EvaluationEngine::RAW_DATA_WARNING }

    it "warns once when built while debug logging is enabled" do
      allow(logger).to receive(:debug?).and_return(true)

      component
      expect(logger).to have_received(:warn).with(raw_data_warning).once

      component.debug_logging_hook
      expect(logger).to have_received(:warn).with(raw_data_warning).once
    end

    it "does not warn while debug logging is disabled" do
      component.debug_logging_hook

      expect(logger).not_to have_received(:warn)
    end

    it "warns once before handing out the debug logging hook when debug logging is enabled later" do
      component
      allow(logger).to receive(:debug?).and_return(true)

      component.debug_logging_hook
      component.debug_logging_hook

      expect(logger).to have_received(:warn).with(raw_data_warning).once
    end
  end

  describe "#shutdown!" do
    before do
      settings.open_feature.enabled = true
      settings.remote.enabled = true
      stub_const("Datadog::Core::LIBDATADOG_API_FAILURE", nil)
    end

    subject(:component) { described_class.new(settings, agent_settings, logger: logger, telemetry: telemetry) }

    it "gracefully shutdown the worker" do
      expect(worker).to receive(:graceful_shutdown)

      component.shutdown!
    end

    context "when span enrichment is enabled" do
      before do
        stub_const("Datadog::Core::LIBDATADOG_API_FAILURE", nil)
        settings.open_feature.span_enrichment_enabled = true
        allow(worker).to receive(:graceful_shutdown)
      end

      it "shuts down the span enrichment hook (symmetric teardown)" do
        expect(component.span_enrichment_hook).to receive(:shutdown)

        component.shutdown!
      end
    end

    # Shutdown stops the EVP writer (which drains + final-flushes its queue).
    # Only meaningful when the SDK supports hooks (>= 0.5) — skip on the min appraisal.
    it "stops the EVP flagevaluation writer so it drains and flushes",
      skip: !Datadog::OpenFeature::Hooks::FlagEvalEVPHook.available? do
      evp_writer = component.instance_variable_get(:@flag_eval_evp_writer)
      expect(evp_writer).to be_a(Datadog::OpenFeature::FlagEvaluation::Writer)
      expect(evp_writer).to receive(:stop)
      allow(worker).to receive(:graceful_shutdown)

      component.shutdown!
    end

    context "with agentless event delivery" do
      subject(:component) do
        described_class.new(settings, agent_settings, resolution: resolution, logger: logger, telemetry: telemetry)
      end

      let(:event_transport) { instance_double(Datadog::OpenFeature::Transport::Agentless) }

      before do
        allow(Datadog::OpenFeature::Transport::Agentless).to receive(:new).and_return(event_transport)
      end

      it "starts the deadline before stopping either writer and closes delivery last",
        skip: !Datadog::OpenFeature::Hooks::FlagEvalEVPHook.available? do
        evaluation_writer = instance_double(Datadog::OpenFeature::FlagEvaluation::Writer)
        allow(Datadog::OpenFeature::FlagEvaluation::Writer).to receive(:new).and_return(evaluation_writer)
        expect(event_transport).to receive(:shutdown!).with(timeout: 5).ordered
        expect(evaluation_writer).to receive(:request_stop).ordered
        expect(worker).to receive(:graceful_shutdown).ordered
        expect(evaluation_writer).to receive(:stop).ordered
        expect(event_transport).to receive(:close).ordered

        component.shutdown!
      end

      it "flushes flag evaluations while the exposure worker is still shutting down",
        skip: !Datadog::OpenFeature::Hooks::FlagEvalEVPHook.available? do
        exposure_started = Queue.new
        exposure_stopping = Queue.new
        release_exposure = Queue.new
        evaluations = Queue.new
        closed = false
        exposure_worker = nil
        evaluation_writer = nil
        allow(Datadog::Core::Utils::Time).to receive(:get_time).and_return(0.0)
        allow_any_instance_of(Datadog::OpenFeature::FlagEvaluation::Writer)
          .to receive(:start_background_thread).and_call_original
        allow(Datadog::OpenFeature::Exposures::Worker).to receive(:new).and_wrap_original do |constructor, **options|
          exposure_worker = constructor.call(**options)
        end
        allow(Datadog::OpenFeature::FlagEvaluation::Writer).to receive(:new).and_wrap_original do |constructor, **options|
          evaluation_writer = constructor.call(**options)
        end
        allow(event_transport).to receive(:shutdown!).with(timeout: 5)
        allow(event_transport).to receive(:close) { closed = true }
        allow(event_transport).to receive(:send_exposures) do
          exposure_started << true
          release_exposure.pop
          Datadog::OpenFeature::Transport::Response.new(code: 202)
        end
        allow(event_transport).to receive(:send_flag_evaluations) do |payload|
          evaluations << [payload, closed]
          Datadog::OpenFeature::Transport::Response.new(code: 202)
        end
        component
        allow(exposure_worker).to receive(:graceful_shutdown).and_wrap_original do |method|
          exposure_stopping << true
          method.call
        end
        exposure_worker.enqueue(
          timestamp: 1_735_689_600_000,
          allocation: {key: "control"},
          flag: {key: "exposure-flag"},
          variant: {key: "on"},
          subject: {id: "subject"},
        )
        Timeout.timeout(1) { exposure_started.pop }
        evaluation_writer.enqueue(flag_key: "shutdown-flag", variant: "on", eval_time_ms: 1_000)

        shutdown_thread = Thread.new { component.shutdown! }
        Timeout.timeout(1) { exposure_stopping.pop }
        payload, closed_during_send = Timeout.timeout(1) { evaluations.pop }
        expect(payload["flagEvaluations"].map { |event| event["flag"]["key"] }).to eq(["shutdown-flag"])
        expect(closed_during_send).to be(false)
        expect(shutdown_thread).to be_alive
        expect(closed).to be(false)

        release_exposure << true
        expect(shutdown_thread.join(1)).to eq(shutdown_thread)
        expect(exposure_worker).not_to be_running
        expect(evaluation_writer).not_to be_running
        expect(closed).to be(true)
        expect(event_transport).to have_received(:send_flag_evaluations).once
      ensure
        release_exposure << true if release_exposure
        shutdown_thread&.join(1)
        shutdown_thread&.kill
        shutdown_thread&.join(1)
        exposure_worker&.stop(true, 0)
        evaluation_writer&.stop
      end
    end
  end

  describe "configuration readiness" do
    before do
      settings.open_feature.enabled = true
      settings.open_feature.evaluation_counts_enabled = false
      settings.feature_flags.initialization_timeout_ms = 1
      settings.remote.enabled = true
      stub_const("Datadog::Core::LIBDATADOG_API_FAILURE", nil)
      allow(worker).to receive(:graceful_shutdown)
    end

    subject(:component) do
      described_class.new(
        settings,
        agent_settings,
        on_configuration_change: on_configuration_change,
        logger: logger,
        telemetry: telemetry,
      )
    end

    describe "#reconfigure!" do
      it "marks an accepted configuration as received" do
        allow(component.engine).to receive(:reconfigure!).with("configuration")

        expect { component.reconfigure!("configuration") }
          .to change(component, :configuration_received?).from(false).to(true)
        expect(on_configuration_change).to have_received(:call).with(:ready)
      end

      it "does not mark a rejected configuration as received" do
        allow(component.engine).to receive(:reconfigure!)
          .and_raise(Datadog::OpenFeature::EvaluationEngine::ReconfigurationError)

        expect { component.reconfigure!("invalid") }
          .to raise_error(Datadog::OpenFeature::EvaluationEngine::ReconfigurationError)
        expect(component.configuration_received?).to be(false)
        expect(on_configuration_change).not_to have_received(:call)
      end

      it "reports subsequent accepted configurations as changed" do
        allow(component.engine).to receive(:reconfigure!)
        component.reconfigure!("first")

        component.reconfigure!("second")

        expect(on_configuration_change).to have_received(:call).with(:changed).once
      end

      it "clears readiness when configuration is deleted" do
        allow(component.engine).to receive(:reconfigure!)
        component.reconfigure!("configuration")

        expect { component.reconfigure!(nil) }
          .to change(component, :configuration_received?).from(true).to(false)
        expect(on_configuration_change).to have_received(:call).with(:ready).once
        expect(on_configuration_change).to have_received(:call).with(:lost).once
      end

      it "reports configuration recovery as ready" do
        events = []
        allow(on_configuration_change).to receive(:call) { |event| events << event }
        allow(component.engine).to receive(:reconfigure!)
        component.reconfigure!("first")
        component.reconfigure!(nil)

        component.reconfigure!("second")

        expect(events).to eq([:ready, :lost, :ready])
      end
    end

    describe "#wait_for_configuration" do
      it "returns ready when configuration was already received" do
        allow(component.engine).to receive(:reconfigure!)
        component.reconfigure!("configuration")

        expect(component.wait_for_configuration).to eq(:ready)
      end

      it "returns timeout when no configuration arrives" do
        allow(Datadog::Core::Utils::Time).to receive(:get_time).and_return(0.0, 1.0)

        expect(component.wait_for_configuration).to eq(:timeout)
      end

      it "times out while configuration is still being applied" do
        reconfiguration_started = SizedQueue.new(1)
        finish_reconfiguration = SizedQueue.new(1)
        allow(component.engine).to receive(:reconfigure!) do
          reconfiguration_started << true
          finish_reconfiguration.pop
        end
        reconfiguration_thread = Thread.new { component.reconfigure!("configuration") }

        begin
          Timeout.timeout(1) { reconfiguration_started.pop }
          allow(Datadog::Core::Utils::Time).to receive(:get_time).and_return(0.0, 1.0)

          expect(Timeout.timeout(1) { component.wait_for_configuration }).to eq(:timeout)
        ensure
          finish_reconfiguration << true
          unless reconfiguration_thread.join(1)
            reconfiguration_thread.kill
            reconfiguration_thread.join(1)
          end
        end
      end

      it "reports shutdown instead of stale readiness" do
        allow(component.engine).to receive(:reconfigure!)
        component.reconfigure!("configuration")
        component.shutdown!

        expect(component.wait_for_configuration).to eq(:shutdown)
      end

      it "wakes when configuration arrives" do
        wait_started = SizedQueue.new(1)
        result = SizedQueue.new(1)
        allow_any_instance_of(ConditionVariable).to receive(:wait).and_wrap_original do |method, *arguments|
          begin
            wait_started.push(true, true)
          rescue ThreadError
            # The waiter has already signaled.
          end
          method.call(*arguments)
        end
        settings.feature_flags.initialization_timeout_ms = 30_000
        waiting_thread = Thread.new { result << component.wait_for_configuration }
        begin
          Timeout.timeout(1) { wait_started.pop }
          allow(component.engine).to receive(:reconfigure!).with("configuration")

          component.reconfigure!("configuration")

          expect(Timeout.timeout(1) { result.pop }).to eq(:ready)
          expect(waiting_thread.join(1)).to eq(waiting_thread)
        ensure
          waiting_thread.kill
          waiting_thread.join(1)
        end
      end

      it "wakes when the component shuts down" do
        wait_started = SizedQueue.new(1)
        result = SizedQueue.new(1)
        allow_any_instance_of(ConditionVariable).to receive(:wait).and_wrap_original do |method, *arguments|
          begin
            wait_started.push(true, true)
          rescue ThreadError
            # The waiter has already signaled.
          end
          method.call(*arguments)
        end
        settings.feature_flags.initialization_timeout_ms = 30_000
        waiting_thread = Thread.new { result << component.wait_for_configuration }
        begin
          Timeout.timeout(1) { wait_started.pop }

          component.shutdown!

          expect(Timeout.timeout(1) { result.pop }).to eq(:shutdown)
          expect(waiting_thread.join(1)).to eq(waiting_thread)
        ensure
          waiting_thread.kill
          waiting_thread.join(1)
        end
      end
    end
  end
end
