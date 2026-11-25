require "spec_helper"

require "datadog/core/telemetry/component"

RSpec.describe Datadog::Core::Telemetry::NativeBackend do
  subject(:backend) do
    described_class.new(
      settings: settings,
      agent_settings: agent_settings,
      logger: logger,
      enabled: enabled,
    )
  end

  let(:settings) do
    Datadog::Core::Configuration::Settings.new.tap do |c|
      c.telemetry.enabled = enabled
      c.telemetry.native_worker = true
      c.telemetry.metrics_enabled = metrics_enabled
      c.telemetry.log_collection_enabled = true
      c.telemetry.shutdown_timeout_seconds = shutdown_timeout_seconds
      c.service = "service_name"
      c.env = "env_name"
      c.version = "service_version"
      c.agent.host = "127.0.0.1"
      c.agent.port = 8126
    end
  end

  let(:agent_settings) { Datadog::Core::Configuration::AgentSettingsResolver.call(settings, logger: nil) }
  let(:enabled) { true }
  let(:metrics_enabled) { true }
  let(:shutdown_timeout_seconds) { 1.0 }
  let(:logger) { instance_double(Logger).as_null_object }
  let(:native_worker) { instance_double(Datadog::Core::Telemetry::Native::Worker) }
  let(:ruby_worker) { double(Datadog::Core::Telemetry::Worker) }
  let(:native_worker_args) { {} }

  # A stand-in for the C extension class. stub_const restores the original
  # constant (when the real extension is loaded) after each example.
  let(:native_worker_class) do
    Class.new do
      def self._native_new(**_args)
        raise "stub me"
      end
    end
  end

  before do
    stub_const("Datadog::Core::LIBDATADOG_API_FAILURE", nil)
    stub_const("Datadog::Core::Telemetry::Native::Worker", native_worker_class)
    allow(native_worker_class).to receive(:_native_new).and_wrap_original do |_method, **args|
      native_worker_args.merge!(args)
      native_worker
    end

    allow(Datadog::Core::Telemetry::Worker).to receive(:new).and_return(ruby_worker)
    allow(ruby_worker).to receive(:start)
    allow(ruby_worker).to receive(:enqueue)
    allow(ruby_worker).to receive(:stop)
    allow(ruby_worker).to receive(:flush)
    allow(ruby_worker).to receive(:"enabled=")
    allow(ruby_worker).to receive(:after_fork_monkey_patched)

    allow(native_worker).to receive(:_start)
    allow(native_worker).to receive(:_shutdown)
    allow(native_worker).to receive(:_register_metric_context).and_return(:context)
    allow(native_worker).to receive(:_add_point)
    allow(native_worker).to receive(:_add_log)
    allow(native_worker).to receive(:_add_config)
    allow(native_worker).to receive(:_add_dependency)
    allow(native_worker).to receive(:_add_integration)
    allow(native_worker).to receive(:_add_endpoint)
  end

  after do
    backend.shutdown!
  end

  describe ".unsupported_reason" do
    it "is nil when the extension and worker are available" do
      expect(described_class.unsupported_reason).to be_nil
    end

    it "reports the extension failure when the extension is missing" do
      stub_const("Datadog::Core::LIBDATADOG_API_FAILURE", "LoadError: nope")

      expect(described_class.unsupported_reason).to eq "LoadError: nope"
    end
  end

  describe "native worker construction" do
    it "builds one native worker with the emitter fields" do
      backend

      expect(native_worker_args[:url]).to start_with "http://127.0.0.1:8126"
      expect(native_worker_args[:timeout_milliseconds]).to be > 0
      expect(native_worker_args[:service_name]).to eq "service_name"
      expect(native_worker_args[:language_name]).to eq "ruby"
      expect(native_worker_args[:language_version]).to eq Datadog::Core::Environment::Ext::LANG_VERSION
      expect(native_worker_args[:tracer_version]).to eq Datadog::Core::Environment::Identity.gem_datadog_version_semver2
      expect(native_worker_args[:env]).to eq "env_name"
      expect(native_worker_args[:service_version]).to eq "service_version"
      expect(native_worker_args[:runtime_name]).to eq Datadog::Core::Environment::Ext::RUBY_ENGINE
      expect(native_worker_args[:runtime_id]).to eq Datadog::Core::Environment::Identity.id
      expect(native_worker_args[:hostname]).to be_a(String)
      expect(native_worker_args[:kernel_name]).to be_a(String)
    end

    context "when telemetry is disabled" do
      let(:enabled) { false }

      it "does not build a native worker" do
        backend

        expect(native_worker_args).to be_empty
      end
    end

    context "when agentless telemetry is enabled" do
      before do
        settings.telemetry.agentless_enabled = true
        allow(settings).to receive(:api_key).and_return("1234")
      end

      it "does not build a native worker and routes metrics through Ruby" do
        expect(backend.native_worker).to be_nil

        backend.inc("tracers", "metric", 1)

        series = backend.metrics_manager.flush!.flat_map { |event| event.payload[:series] }
        expect(series).to include(hash_including(metric: "metric"))
      end
    end
  end

  describe "native worker adoption" do
    let(:previous_backend) do
      described_class.new(
        settings: settings,
        agent_settings: agent_settings,
        logger: logger,
        enabled: enabled,
      )
    end
    let(:native_worker2) do
      instance_double(Datadog::Core::Telemetry::Native::Worker).tap do |worker|
        allow(worker).to receive(:_start)
        allow(worker).to receive(:_shutdown)
        allow(worker).to receive(:_register_metric_context).and_return(:context2)
        allow(worker).to receive(:_add_point)
        allow(worker).to receive(:_add_log)
      end
    end

    it "adopts the previous worker when the settings are unchanged" do
      previous_backend
      worker = previous_backend.native_worker

      new_backend = described_class.new(
        settings: settings,
        agent_settings: agent_settings,
        logger: logger,
        enabled: enabled,
        previous_backend: previous_backend,
      )

      expect(new_backend.native_worker).to be(worker)
      expect(native_worker_class).to have_received(:_native_new).once
    end

    it "keeps the previous metric context cache so metrics are not registered twice" do
      previous_backend.inc("tracers", "metric", 1)

      new_backend = described_class.new(
        settings: settings,
        agent_settings: agent_settings,
        logger: logger,
        enabled: enabled,
        previous_backend: previous_backend,
      )
      new_backend.inc("tracers", "metric", 1)

      expect(native_worker).to have_received(:_register_metric_context).once
      expect(native_worker).to have_received(:_add_point).twice
    end

    it "leaves an adopted worker running when the previous backend shuts down" do
      previous_backend
      described_class.new(
        settings: settings,
        agent_settings: agent_settings,
        logger: logger,
        enabled: enabled,
        previous_backend: previous_backend,
      )

      previous_backend.shutdown!

      expect(native_worker).not_to have_received(:_shutdown)
    end

    it "builds a new worker and stops the old one when the settings diverge" do
      previous_backend
      allow(native_worker_class).to receive(:_native_new).and_return(native_worker2)
      settings.service = "other_service"

      new_backend = described_class.new(
        settings: settings,
        agent_settings: agent_settings,
        logger: logger,
        enabled: enabled,
        previous_backend: previous_backend,
      )

      expect(new_backend.native_worker).to be(native_worker2)
      expect(previous_backend.native_worker).to be(native_worker)

      previous_backend.shutdown!

      expect(native_worker).to have_received(:_shutdown)
      expect(native_worker2).not_to have_received(:_shutdown)
    end

    it "builds a new worker when the previous backend has none" do
      previous_backend.after_fork

      new_backend = described_class.new(
        settings: settings,
        agent_settings: agent_settings,
        logger: logger,
        enabled: enabled,
        previous_backend: previous_backend,
      )

      expect(new_backend.native_worker).to be(native_worker)
      expect(native_worker_class).to have_received(:_native_new).twice
    end
  end

  describe "metric methods" do
    it "registers one context per metric and adds points with tag pairs" do
      backend.inc("tracers", "metric", 5, tags: ["a:b"], common: true)
      backend.inc("tracers", "metric", 3, tags: {"c" => "d"})

      expect(native_worker).to have_received(:_register_metric_context)
        .with("metric", :count, true, :tracers).once
      expect(native_worker).to have_received(:_add_point).with(:context, 5, [["a", "b"]])
      expect(native_worker).to have_received(:_add_point).with(:context, 3, [["c", "d"]])
    end

    it "dec submits a negative count point" do
      backend.dec("tracers", "metric", 2)

      expect(native_worker).to have_received(:_register_metric_context)
        .with("metric", :count, true, :tracers)
      expect(native_worker).to have_received(:_add_point).with(:context, -2, [])
    end

    it "gauge, rate, and distribution register their metric types" do
      backend.gauge("tracers", "m_gauge", 1)
      backend.rate("tracers", "m_rate", 2)
      backend.distribution("tracers", "m_dist", 3)

      expect(native_worker).to have_received(:_register_metric_context)
        .with("m_gauge", :gauge, true, :tracers)
      expect(native_worker).to have_received(:_register_metric_context)
        .with("m_rate", :rate, true, :tracers)
      expect(native_worker).to have_received(:_register_metric_context)
        .with("m_dist", :distribution, true, :tracers)
    end

    it "registers a separate context when common differs" do
      backend.inc("tracers", "metric", 1, common: true)
      backend.inc("tracers", "metric", 1, common: false)

      expect(native_worker).to have_received(:_register_metric_context).twice
    end

    context "when metrics are disabled" do
      let(:metrics_enabled) { false }

      it "does not add points" do
        backend.inc("tracers", "metric", 1)

        expect(native_worker).not_to have_received(:_add_point)
      end
    end

    context "when the native call raises" do
      before do
        allow(native_worker).to receive(:_add_point).and_raise(RuntimeError, "boom")
      end

      it "swallows the error" do
        expect { backend.inc("tracers", "metric", 1) }.not_to raise_error
      end
    end
  end

  describe "#add_log" do
    let(:log_event) do
      Datadog::Core::Telemetry::Event::Log.new(message: "message", level: :error, stack_trace: "trace")
    end

    it "sends the log to the native worker" do
      backend.add_log(log_event)

      expect(native_worker).to have_received(:_add_log).with("message", "message", :error, "trace")
    end

    it "falls back to the Ruby event queue when there is no native worker" do
      backend.after_fork

      backend.add_log(log_event)

      expect(ruby_worker).to have_received(:enqueue).with(log_event)
    end
  end

  describe "#start" do
    let(:components) do
      instance_double(Datadog::Core::Configuration::Components).tap do |components|
        allow(components).to receive(:settings).and_return(settings)
        allow(components).to receive(:agent_settings).and_return(agent_settings)
        allow(components).to receive(:appsec).and_return(nil)
        allow(components).to receive(:profiler).and_return(nil)
        allow(components).to receive(:dynamic_instrumentation).and_return(nil)
      end
    end
    let(:app_started_event) do
      Datadog::Core::Telemetry::Event::AppStarted.new(components: components)
    end

    before do
      allow(ruby_worker).to receive(:prepare_initial_event)
    end

    it "feeds the configuration snapshot through the builder and does not run the Ruby event worker" do
      allow(native_worker).to receive(:_add_dependency)

      backend.start(app_started_event)

      expect(native_worker_args[:initial_configuration]).to include(
        ["tracing.auto_instrument.enabled", "false", :default, nil, 1],
      )
      expect(native_worker).not_to have_received(:_add_config)
      expect(native_worker).to have_received(:_start).once
      expect(ruby_worker).not_to have_received(:start)
      expect(ruby_worker).to have_received(:prepare_initial_event).with(app_started_event)
    end

    it "feeds dependencies when collection is enabled" do
      backend.start(app_started_event)

      expect(native_worker).to have_received(:_add_dependency)
        .with("rspec-core", Gem.loaded_specs["rspec-core"].version.to_s)
    end

    context "when dependency collection is disabled" do
      before { settings.telemetry.dependency_collection = false }

      it "does not feed dependencies" do
        backend.start(app_started_event)

        expect(native_worker).not_to have_received(:_add_dependency)
      end
    end

    it "feeds a reconfigure snapshot through handle calls on an adopted worker" do
      previous_backend = described_class.new(
        settings: settings,
        agent_settings: agent_settings,
        logger: logger,
        enabled: enabled,
      )
      new_backend = described_class.new(
        settings: settings,
        agent_settings: agent_settings,
        logger: logger,
        enabled: enabled,
        previous_backend: previous_backend,
      )
      synth = Datadog::Core::Telemetry::Event::SynthAppClientConfigurationChange.new(components: components)

      new_backend.start(synth)

      expect(native_worker).to have_received(:_add_config).at_least(:once)
      expect(native_worker).to have_received(:_start).once
      expect(ruby_worker).to have_received(:prepare_initial_event).with(synth)
    end

    context "when there is no native worker" do
      before { backend.after_fork }

      it "starts the Ruby event worker with the initial event" do
        backend.start(:initial_event)

        expect(ruby_worker).to have_received(:start).with(:initial_event)
        expect(native_worker).not_to have_received(:_start)
      end
    end
  end

  describe "#enqueue" do
    let(:worker_nil_backend) do
      backend.after_fork
      backend
    end

    it "routes remote configuration changes to _add_config" do
      changes = Datadog::Core::Telemetry::Event::AppClientConfigurationChange.new({"tracing.sample_rate" => 1.0}, "remote_config")

      backend.enqueue(changes)

      expect(native_worker).to have_received(:_add_config)
        .with("tracing.sample_rate", "1.0", :remote_config, nil, 6)
    end

    it "routes dependencies-loaded to _add_dependency" do
      deps = Datadog::Core::Telemetry::Event::AppDependenciesLoaded.new

      backend.enqueue(deps)

      expect(native_worker).to have_received(:_add_dependency).at_least(:once)
      expect(ruby_worker).not_to have_received(:enqueue)
    end

    it "routes integrations-change to _add_integration" do
      integrations = Datadog::Core::Telemetry::Event::AppIntegrationsChange.new

      backend.enqueue(integrations)

      expect(native_worker).to have_received(:_add_integration).at_least(:once)
    end

    it "routes endpoints to _add_endpoint without page slicing" do
      endpoints = [
        {type: "REST", method: "GET", path: "/events", operation_name: "http.request", resource_name: "GET /events"},
        {type: "REST", method: "POST", path: "/events", operation_name: "http.request", resource_name: "POST /events"},
      ]
      event = Datadog::Core::Telemetry::Event::AppEndpointsLoaded.new(endpoints, is_first: true)

      backend.enqueue(event)

      expect(native_worker).to have_received(:_add_endpoint)
        .with("GET", "/events", "http.request", "GET /events")
        .with("POST", "/events", "http.request", "POST /events")
    end

    it "drops closing and heartbeat events, emitted by the native worker itself" do
      backend.enqueue(Datadog::Core::Telemetry::Event::AppClosing.new)
      backend.enqueue(Datadog::Core::Telemetry::Event::AppHeartbeat.new)

      expect(ruby_worker).not_to have_received(:enqueue)
    end

    context "when there is no native worker" do
      it "enqueues on the Ruby event worker" do
        worker_nil_backend.enqueue(Datadog::Core::Telemetry::Event::AppClosing.new)

        expect(ruby_worker).to have_received(:enqueue)
      end
    end
  end

  describe "#after_fork" do
    it "drops the native worker and falls back to Ruby metrics" do
      backend.inc("tracers", "metric", 1)
      backend.after_fork

      expect(backend.native_worker).to be_nil

      backend.inc("tracers", "metric", 4)

      expect(native_worker).to have_received(:_add_point).once
      series = backend.metrics_manager.flush!.flat_map { |event| event.payload[:series] }
      expect(series).to include(hash_including(metric: "metric"))
    end
  end

  describe "#shutdown!" do
    it "shuts down the native worker with the configured timeout" do
      backend.shutdown!

      expect(native_worker).to have_received(:_shutdown).with(1000)
    end
  end

  describe "Component integration" do
    subject(:component) do
      Datadog::Core::Telemetry::Component.new(
        settings: settings,
        agent_settings: agent_settings,
        logger: logger,
        enabled: enabled,
      )
    end

    it "selects the native backend" do
      expect(component.backend).to be_a(described_class)
    end

    context "when native_worker is disabled" do
      before do
        settings.telemetry.native_worker = false
      end

      it "selects the Ruby backend" do
        expect(component.backend).to be_a(Datadog::Core::Telemetry::RubyBackend)
        expect(component.backend).not_to be_a(described_class)
      end
    end

    context "when the extension is unavailable" do
      before do
        stub_const("Datadog::Core::LIBDATADOG_API_FAILURE", "LoadError: nope")
      end

      it "selects the Ruby backend" do
        expect(component.backend).to be_a(Datadog::Core::Telemetry::RubyBackend)
        expect(component.backend).not_to be_a(described_class)
      end
    end
  end
end
