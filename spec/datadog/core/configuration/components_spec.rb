require "spec_helper"
require "datadog/di/spec_helper"
require "datadog/profiling/spec_helper"

require "logger"

require "datadog/core/configuration/components"
require "datadog/core/diagnostics/environment_logger"
require "datadog/core/diagnostics/health"
require "datadog/core/logger"
require "datadog/core/telemetry/component"
require "datadog/core/runtime/metrics"
require "datadog/core/workers/runtime_metrics"
require "datadog/statsd"
require "datadog/core/configuration/agent_settings_resolver"
require "datadog/core/transport/http/adapters/net"
require "datadog/tracing/tracer"

# TODO: Components contains behavior for all of the different products.
#       Test behavior needs to be extracted to complimentary component files for every product.
RSpec.describe Datadog::Core::Configuration::Components do
  subject(:components) { described_class.new(settings) }

  let(:logger) do
    instance_double(Datadog::Core::Logger).tap do |logger|
      allow(logger).to receive(:debug)
      # DI::Component.build is now invoked unconditionally during Components
      # construction. When the DI C extension is not compiled (the default
      # for `test:main`), build emits a customer-actionable warn that is
      # unrelated to whatever the surrounding test is exercising.
      allow(logger).to receive(:warn).with(/C extension is not available/)
    end
  end
  let(:settings) { Datadog::Core::Configuration::Settings.new }
  let(:agent_settings) { Datadog::Core::Configuration::AgentSettingsResolver.call(settings, logger: nil) }
  let(:agent_info) { Datadog::Core::Environment::AgentInfo.new(agent_settings, logger: logger) }

  let(:profiler_setup_task) { Datadog::Profiling.supported? ? instance_double(Datadog::Profiling::Tasks::Setup) : nil }
  let(:remote) { instance_double(Datadog::Core::Remote::Component, start: nil, shutdown!: nil, started?: false, add_products: nil, remove_products: nil) }
  let(:telemetry) do
    instance_double(Datadog::Core::Telemetry::Component).tap do |telemetry|
      allow(telemetry).to receive(:start)
      allow(telemetry).to receive(:enabled).and_return(false)
    end
  end

  let(:environment_logger_extra) { {hello: 123, world: "456"} }

  include_context "non-development execution environment"

  before do
    # Ensure the real task never gets run (so it doesn't apply our thread patches and other extensions to our test env)
    if Datadog::Profiling.supported?
      allow(Datadog::Profiling::Tasks::Setup).to receive(:new).and_return(profiler_setup_task)
    end
    allow(Datadog::Statsd).to receive(:new) { instance_double(Datadog::Statsd) }
    allow(Datadog::Core::Remote::Component).to receive(:new).and_return(remote)
    allow(Datadog::Core::Telemetry::Component).to receive(:new).and_return(telemetry)
  end

  with_env "DD_REMOTE_CONFIGURATION_ENABLED" => nil

  describe "::new" do
    let(:tracer) { instance_double(Datadog::Tracing::Tracer) }
    let(:profiler) { Datadog::Profiling.supported? ? instance_double(Datadog::Profiling::Profiler) : nil }
    let(:runtime_metrics) { instance_double(Datadog::Core::Workers::RuntimeMetrics) }
    let(:health_metrics) { instance_double(Datadog::Core::Diagnostics::Health::Metrics) }

    before do
      expect(described_class).to receive(:build_logger)
        .with(settings)
        .and_return(logger)

      expect(Datadog::Core::Configuration::StableConfig).to receive(:log_result)
        .with(logger)

      expect(Datadog::Tracing::Component).to receive(:build_tracer)
        .with(settings, agent_settings, logger: logger)
        .and_return(tracer)

      crashtracker = double("crashtracker")
      expect(described_class).to receive(:build_crashtracker)
        .with(settings, agent_settings, logger: logger)
        .and_return(crashtracker)

      expect(Datadog::Profiling::Component).to receive(:build_profiler_component).with(
        settings: settings,
        agent_settings: agent_settings,
        optional_tracer: tracer,
        logger: logger,
      ).and_return([profiler, environment_logger_extra])

      expect(described_class).to receive(:build_runtime_metrics_worker)
        .with(settings, logger, telemetry)
        .and_return(runtime_metrics)

      expect(described_class).to receive(:build_health_metrics)
        .with(settings, logger, telemetry)
        .and_return(health_metrics)

      expect(Datadog::Core::Configuration::Deprecations).to receive(:log_deprecations_from_all_sources)
        .with(logger)
    end

    it do
      expect(components.logger).to be logger
      expect(components.tracer).to be tracer
      expect(components.profiler).to be profiler
      expect(components.runtime_metrics).to be runtime_metrics
      expect(components.health_metrics).to be health_metrics
      expect(components.agent_info).to eq agent_info
    end

    describe "@environment_logger_extra" do
      let(:environment_logger_extra) { {} }

      let(:extra) do
        components.instance_variable_get(:@environment_logger_extra)
      end

      context "DI is not enabled" do
        # The DI component is now always built when settings respond to
        # dynamic_instrumentation (regardless of the env-var enabled flag),
        # so it can be started later by remote config if the customer turns
        # it on from the UI. With the env-var unset, the component is built
        # but stays stopped (not started?), and the env logger reports the
        # customer-configured value as false.
        let(:stub_di_component) do
          instance_double(Datadog::DI::Component, started?: false, shutdown!: nil)
        end

        before do
          allow(Datadog::DI::Component).to receive(:build).and_return(stub_di_component)
        end

        it "builds the component but reports DI as disabled" do
          expect(components.dynamic_instrumentation).to be(stub_di_component)
          expect(components.dynamic_instrumentation.started?).to be false
          expect(extra).to eq(dynamic_instrumentation_enabled: false)
        end
      end

      context "DI is enabled" do
        before(:all) do
          skip "DI is disabled due to Ruby version < 2.6" if RubyVersion.is?("< 2.6")
        end

        before do
          settings.dynamic_instrumentation.enabled = true
        end

        after do
          # Shutdown DI if present because it creates a background thread.
          # On JRuby DI is not present.
          components.dynamic_instrumentation&.shutdown!
        end

        context "MRI with C extension" do
          before(:all) do
            skip "Test requires MRI" if PlatformHelpers.jruby?
          end

          let(:stub_di_component) { instance_double(Datadog::DI::Component, started?: true, shutdown!: nil) }

          before do
            allow(Datadog::DI::Component).to receive(:build).and_return(stub_di_component)
          end

          it "reports DI as enabled" do
            expect(components.dynamic_instrumentation).to be(stub_di_component)
            expect(extra).to eq(dynamic_instrumentation_enabled: true)
          end
        end

        context "MRI without C extension" do
          before(:all) do
            skip "Test requires MRI" if PlatformHelpers.jruby?
          end

          before do
            # Make Component.build behave as if the C extension is absent: the
            # real build path checks `DI.respond_to?(:exception_message)` and
            # warns + returns nil when the method is missing. Stubbing
            # respond_to? lets the test exercise that branch regardless of
            # whether the C extension is actually compiled in this build.
            allow(Datadog::DI).to receive(:respond_to?).and_call_original
            allow(Datadog::DI).to receive(:respond_to?).with(:exception_message).and_return(false)
          end

          it "reports DI as disabled" do
            expect(logger).to receive(:warn).with(/C extension is not available/)
            expect(components.dynamic_instrumentation).to be nil
            expect(extra).to eq(dynamic_instrumentation_enabled: false)
          end
        end

        context "JRuby" do
          before(:all) do
            skip "Test requires JRuby" unless PlatformHelpers.jruby?
          end

          it "reports DI as disabled" do
            expect(logger).to receive(:warn).with(/MRI is required.*jruby/)
            expect(components.dynamic_instrumentation).to be nil
            expect(extra).to eq(dynamic_instrumentation_enabled: false)
          end
        end
      end
    end

    describe "@symbol_database" do
      context "when symbol_database is disabled" do
        before { settings.symbol_database.enabled = false }

        it "does not build a symbol database component" do
          expect(components.symbol_database).to be nil
        end
      end

      context "when symbol_database is enabled with remote config" do
        before(:all) do
          skip "Symbol database requires MRI Ruby 2.7+" if PlatformHelpers.jruby? || RubyVersion.is?("< 2.7")
        end

        before do
          settings.symbol_database.enabled = true
          settings.remote.enabled = true
        end

        after { components.symbol_database&.shutdown! }

        it "builds a symbol database component" do
          expect(components.symbol_database).to be_a(Datadog::SymbolDatabase::Component)
        end
      end
    end
  end

  describe "::enable_symbol_database?" do
    subject(:enabled?) { described_class.enable_symbol_database?(settings, dynamic_instrumentation) }

    let(:settings) { Datadog::Core::Configuration::Settings.new }
    # enable_symbol_database? decides whether to BUILD the component. A non-nil
    # DI component stands for "DI's component was built" (DI not explicitly
    # disabled, runtime supported); nil stands for "DI's component was not
    # built". The resolver never calls a method on it, only checks presence.
    # Whether a built component actually uploads is gated separately, at upload
    # time, on DI being active, by SymbolDatabase::Component#upload_allowed?.
    let(:dynamic_instrumentation) { instance_double(Datadog::DI::Component) }

    context "when the symbol_database settings group is not registered (partial load)" do
      # A plain double models a Settings object that lacks the dynamically-added
      # symbol_database group, e.g. require 'datadog/di' without the full library.
      let(:settings) { double("settings without symbol_database group") }

      before { allow(settings).to receive(:respond_to?).with(:symbol_database).and_return(false) }

      it "returns false even when DI is running" do
        is_expected.to be false
      end
    end

    context "when symbol_database.enabled is explicitly true" do
      before { settings.symbol_database.enabled = true }

      let(:dynamic_instrumentation) { nil }

      it "returns true even when DI is not running" do
        is_expected.to be true
      end
    end

    context "when symbol_database.enabled is explicitly false" do
      before { settings.symbol_database.enabled = false }

      it "returns false even when DI is running" do
        is_expected.to be false
      end
    end

    context "when symbol_database.enabled is unset (nil)" do
      before { settings.symbol_database.enabled = nil }

      context "and DI's component was built" do
        let(:dynamic_instrumentation) { instance_double(Datadog::DI::Component) }

        it { is_expected.to be true }
      end

      context "and DI's component was not built (nil)" do
        let(:dynamic_instrumentation) { nil }

        it { is_expected.to be false }
      end

      context "and dynamic_instrumentation.enabled is true but DI did not start" do
        # e.g. Rails development mode or a missing DI C extension: the setting is
        # true but DI::Component.build returned nil. The default must follow DI's
        # runtime readiness, not the setting, so no symbol extraction happens.
        before { settings.dynamic_instrumentation.enabled = true }

        let(:dynamic_instrumentation) { nil }

        it "returns false" do
          is_expected.to be false
        end
      end

      context "and force_upload is set" do
        # force_upload uploads unconditionally, so the component must be built
        # even when the setting is nil and DI's component was not built —
        # otherwise the force-upload path is unreachable.
        before { settings.symbol_database.internal.force_upload = true }

        let(:dynamic_instrumentation) { nil }

        it "returns true even when DI is not running" do
          is_expected.to be true
        end
      end
    end
  end

  describe "::build_health_metrics" do
    subject(:build_health_metrics) { described_class.build_health_metrics(settings, logger, telemetry) }

    context "given settings" do
      shared_examples_for "new health metrics" do
        let(:health_metrics) { instance_double(Datadog::Core::Diagnostics::Health::Metrics) }
        let(:default_options) { {enabled: settings.health_metrics.enabled} }
        let(:options) { {} }

        before do
          expect(Datadog::Core::Diagnostics::Health::Metrics).to receive(:new)
            .with(default_options.merge(options).merge(logger: logger, telemetry: telemetry))
            .and_return(health_metrics)
        end

        it { is_expected.to be(health_metrics) }
      end

      context "by default" do
        it_behaves_like "new health metrics"
      end

      context "with :enabled" do
        let(:enabled) { double("enabled") }

        before do
          allow(settings.health_metrics)
            .to receive(:enabled)
            .and_return(enabled)
        end

        it_behaves_like "new health metrics" do
          let(:options) { {enabled: enabled} }
        end
      end

      context "with :statsd" do
        let(:statsd) { instance_double(Datadog::Statsd) }

        before do
          allow(settings.health_metrics)
            .to receive(:statsd)
            .and_return(statsd)
        end

        it_behaves_like "new health metrics" do
          let(:options) { {statsd: statsd} }
        end
      end
    end
  end

  describe "::build_logger" do
    subject(:build_logger) { described_class.build_logger(settings) }

    context "given an instance" do
      let(:instance) { instance_double(Datadog::Core::Logger) }

      before do
        expect(settings.logger).to receive(:instance)
          .and_return(instance)

        expect(instance).to receive(:level=)
          .with(settings.logger.level)
      end

      it "uses the logger instance" do
        expect(Datadog::Core::Logger).to_not receive(:new)
        is_expected.to be(instance)
      end
    end

    context "given settings" do
      shared_examples_for "new logger" do
        let(:logger) { instance_double(Datadog::Core::Logger) }
        let(:level) { settings.logger.level }

        before do
          # Build the settings before Core::Logger.new is stubbed: the first
          # settings construction in the process also builds the library's
          # internal logger through Core::Logger.new, and the stub would return
          # this instance double, which rejects its level= call.
          settings

          expect(Datadog::Core::Logger).to receive(:new)
            .with($stderr)
            .and_return(logger)

          expect(logger).to receive(:level=).with(level)
        end

        it { is_expected.to be(logger) }
      end

      context "by default" do
        it_behaves_like "new logger"
      end

      context "with :level" do
        let(:level) { double("level") }

        before do
          allow(settings.logger)
            .to receive(:level)
            .and_return(level)
        end

        it_behaves_like "new logger"
      end

      context "with debug: true" do
        before { settings.diagnostics.debug = true }

        it_behaves_like "new logger" do
          let(:level) { ::Logger::DEBUG }
        end

        context "and a conflicting log level" do
          before do
            allow(settings.logger)
              .to receive(:level)
              .and_return(::Logger::INFO)
          end

          it_behaves_like "new logger" do
            let(:level) { ::Logger::DEBUG }
          end
        end
      end
    end
  end

  describe "::build_telemetry" do
    subject(:build_telemetry) { described_class.build_telemetry(settings, agent_settings, logger) }
    let(:logger) { instance_double(Logger) }

    it "invokes Telemetry::Component.build" do
      expect(Datadog::Core::Telemetry::Component).to receive(:build).with(settings, agent_settings, logger)
      build_telemetry
    end
  end

  describe "::build_runtime_metrics" do
    subject(:build_runtime_metrics) { described_class.build_runtime_metrics(settings, logger, telemetry) }

    context "given settings" do
      shared_examples_for "new runtime metrics" do
        let(:runtime_metrics) { instance_double(Datadog::Core::Runtime::Metrics) }
        let(:default_options) do
          {enabled: settings.runtime_metrics.enabled,
           services: [settings.service],
           experimental_runtime_id_enabled: settings.runtime_metrics.experimental_runtime_id_enabled,
           experimental_propagate_process_tags_enabled: settings.experimental_propagate_process_tags_enabled}
        end
        let(:options) { {} }

        before do
          expect(Datadog::Core::Runtime::Metrics).to receive(:new)
            .with(**default_options.merge(options).merge(logger: logger, telemetry: telemetry))
            .and_return(runtime_metrics)
        end

        it { is_expected.to be(runtime_metrics) }
      end

      context "by default" do
        it_behaves_like "new runtime metrics"
      end

      context "with :enabled" do
        let(:enabled) { double("enabled") }

        before do
          allow(settings.runtime_metrics)
            .to receive(:enabled)
            .and_return(enabled)
        end

        it_behaves_like "new runtime metrics" do
          let(:options) { {enabled: enabled} }
        end
      end

      context "with :service" do
        let(:service) { double("service") }

        before do
          allow(settings)
            .to receive(:service)
            .and_return(service)
        end

        it_behaves_like "new runtime metrics" do
          let(:options) { {services: [service]} }
        end
      end

      context "with :statsd" do
        let(:statsd) { instance_double(::Datadog::Statsd) }

        before do
          allow(settings.runtime_metrics)
            .to receive(:statsd)
            .and_return(statsd)
        end

        it_behaves_like "new runtime metrics" do
          let(:options) { {statsd: statsd} }
        end
      end

      context "with :experimental_runtime_id_enabled" do
        let(:experimental_runtime_id_enabled) { double("experimental_runtime_id_enabled") }

        before do
          allow(settings.runtime_metrics)
            .to receive(:experimental_runtime_id_enabled)
            .and_return(experimental_runtime_id_enabled)
        end

        it_behaves_like "new runtime metrics" do
          let(:options) { {experimental_runtime_id_enabled: experimental_runtime_id_enabled} }
        end
      end
    end
  end

  describe "::build_runtime_metrics_worker" do
    subject(:build_runtime_metrics_worker) { described_class.build_runtime_metrics_worker(settings, logger, telemetry) }

    context "given settings" do
      shared_examples_for "new runtime metrics worker" do
        let(:runtime_metrics_worker) { instance_double(Datadog::Core::Workers::RuntimeMetrics) }
        let(:runtime_metrics) { instance_double(Datadog::Core::Runtime::Metrics) }
        let(:default_options) do
          {
            enabled: settings.runtime_metrics.enabled,
            metrics: runtime_metrics,
          }
        end
        let(:options) { {} }

        before do
          allow(described_class).to receive(:build_runtime_metrics)
            .with(settings, logger, telemetry)
            .and_return(runtime_metrics)

          expect(Datadog::Core::Workers::RuntimeMetrics).to receive(:new)
            .with(**default_options.merge(options).merge(logger: logger, telemetry: telemetry))
            .and_return(runtime_metrics_worker)
        end

        it { is_expected.to be(runtime_metrics_worker) }
      end

      context "by default" do
        it_behaves_like "new runtime metrics worker"
      end

      context "with :enabled" do
        let(:enabled) { double("enabled") }

        before do
          allow(settings.runtime_metrics)
            .to receive(:enabled)
            .and_return(enabled)
        end

        it_behaves_like "new runtime metrics worker" do
          let(:options) { {enabled: enabled} }
        end
      end

      context "with :opts" do
        let(:opts) { {custom_option: :custom_value} }

        before do
          allow(settings.runtime_metrics)
            .to receive(:opts)
            .and_return(opts)
        end

        it_behaves_like "new runtime metrics worker" do
          let(:options) { opts }
        end
      end
    end
  end

  describe "#reconfigure_sampler" do
    subject(:reconfigure_sampler) { components.reconfigure_sampler }

    context "with configuration changes" do
      before do
        Datadog.configuration.tracing.sampling.rate_limit = 123
      end

      it "does not change the sampler delegator object" do
        expect { reconfigure_sampler }.to_not(change { components.tracer.sampler })
      end

      it "changes the sampler delegator's delegatee" do
        expect { reconfigure_sampler }.to(
          change do
            components.tracer.sampler.sampler.priority_sampler.rate_limiter.rate
          end.from(100).to(123),
        )
      end
    end

    context "with test mode enabled" do
      subject(:reconfigure_sampler) { components.reconfigure_sampler(settings) }

      before do
        settings.tracing.test_mode.enabled = true
        settings.tracing.sampling.default_rate = 0.0
      end

      it "keeps the sampler that keeps every trace despite the zero rate" do
        reconfigure_sampler

        delegatee = components.tracer.sampler.sampler
        expect(delegatee).to be_a(Datadog::Tracing::Sampling::PrioritySampler)
        expect(delegatee.pre_sampler).to be_a(Datadog::Tracing::Sampling::AllSampler)
        expect(delegatee.priority_sampler).to be_a(Datadog::Tracing::Sampling::AllSampler)
      end
    end
  end

  describe "#reconfigure_profiler" do
    subject(:reconfigure_profiler) { components.reconfigure_profiler }

    let(:old_profiler) { instance_double(Datadog::Profiling::Profiler, shutdown!: nil, start: nil) }
    let(:new_profiler) { instance_double(Datadog::Profiling::Profiler, shutdown!: nil, start: nil) }

    before do
      components.instance_variable_set(:@profiler, old_profiler)
      allow(Datadog::Profiling::Component).to receive(:build_profiler_component)
        .and_return([new_profiler, {profiling_enabled: true}])
    end

    context "when profiling is enabled" do
      before { settings.profiling.enabled = true }

      it "rebuilds the profiler from the current settings" do
        expect(Datadog::Profiling::Component).to receive(:build_profiler_component) do |**kwargs|
          expect(kwargs).to include(
            settings: settings,
            agent_settings: components.agent_settings,
            optional_tracer: components.tracer,
            logger: components.logger,
          )
          [new_profiler, nil]
        end

        expect { reconfigure_profiler }.to change { components.profiler }.from(old_profiler).to(new_profiler)
      end

      # The native extension permits only one active CpuAndWallTimeWorker, so
      # starting before the old one is stopped would raise.
      it "shuts the old profiler down before starting the new one" do
        expect(old_profiler).to receive(:shutdown!).ordered
        expect(new_profiler).to receive(:start).ordered

        reconfigure_profiler
      end
    end

    context "when profiling is disabled" do
      before do
        settings.profiling.enabled = false
        allow(Datadog::Profiling::Component).to receive(:build_profiler_component)
          .and_return([nil, {profiling_enabled: false}])
      end

      it "shuts the old profiler down and clears it" do
        expect(old_profiler).to receive(:shutdown!)

        expect { reconfigure_profiler }.to change { components.profiler }.from(old_profiler).to(nil)
      end
    end

    context "when profiling is enabled but unsupported" do
      before do
        settings.profiling.enabled = true
        allow(Datadog::Profiling::Component).to receive(:build_profiler_component)
          .and_return([nil, {profiling_enabled: false}])
        allow(Datadog::Profiling).to receive(:unsupported_reason).and_return("test reason")
      end

      it "warns instead of starting" do
        expect(components.logger).to receive(:warn).with(/not supported, profiling disabled: test reason/)

        reconfigure_profiler
      end
    end
  end

  describe "#startup!" do
    subject(:startup!) { components.startup!(settings) }

    it "starts OpenFeature activation" do
      activation = instance_double(Datadog::OpenFeature::Activation, startup!: nil)
      allow(Datadog::OpenFeature::Activation).to receive(:new).and_return(activation)

      expect(activation).to receive(:startup!)

      startup!
    end

    context "when eager OpenFeature delivery raises" do
      let(:error) { RuntimeError.new("test failure") }
      let(:activation) do
        Datadog::OpenFeature::Activation.new(settings, agent_settings, remote, logger: logger, telemetry: telemetry)
      end

      before do
        allow(activation).to receive(:start!).and_raise(error)
        allow(Datadog::OpenFeature::Activation).to receive(:new).and_return(activation)
      end

      it "reports the failure and continues library startup" do
        expect(logger).to receive(:error)
          .with("Feature Flags delivery failed to start: RuntimeError: test failure")
        expect(telemetry).to receive(:report)
          .with(error, description: "Feature Flags delivery failed to start")
        expect(Datadog::Core::ProcessDiscovery).to receive(:publish).with(settings)
        expect(Datadog::Core::Diagnostics::EnvironmentLogger).to receive(:collect_and_log!)

        expect { startup! }.not_to raise_error
      end
    end

    context "when profiling" do
      context "is unsupported" do
        before do
          allow(Datadog::Profiling)
            .to receive(:unsupported_reason)
            .and_return("Disabled for testing")
        end

        context "and enabled" do
          before do
            allow(settings.profiling)
              .to receive(:enabled)
              .and_return(true)
          end

          it do
            expect(components.profiler)
              .to be nil

            expect(components.logger)
              .to receive(:warn)
              .with(/profiling disabled/)

            startup!
          end
        end

        context "and disabled" do
          before do
            allow(settings.profiling)
              .to receive(:enabled)
              .and_return(false)
          end

          it do
            expect(components.profiler)
              .to be nil

            expect(components.logger)
              .to_not receive(:warn)

            startup!
          end
        end
      end

      context "is enabled" do
        # Using a generic double rather than instance_double since if profiling is not supported by the
        # current CI runner we won't even load the Datadog::Profiling::Profiler class.
        let(:profiler) { instance_double("Datadog::Profiling::Profiler") }

        before do
          allow(settings.profiling)
            .to receive(:enabled)
            .and_return(true)
          expect(Datadog::Profiling::Component).to receive(:build_profiler_component).with(
            settings: settings,
            agent_settings: agent_settings,
            optional_tracer: anything,
            logger: anything, # Tested above in "new"
          ).and_return([profiler, environment_logger_extra])
        end

        it do
          expect(profiler).to receive(:start)

          startup!
        end
      end
    end

    context "with remote" do
      shared_context "stub remote configuration agent response" do
        before do
          WebMock.enable!
          stub_request(:get, %r{/info}).to_return(body: info_response, status: 200)
          stub_request(:post, %r{/v0\.7/config}).to_return(body: "{}", status: 200)
        end

        after { WebMock.disable! }

        let(:info_response) { {endpoints: ["/v0.7/config"]}.to_json }
      end

      context "disabled" do
        before { allow(settings.remote).to receive(:enabled).and_return(false) }

        it "does not start the remote manager" do
          startup!
          expect(components.remote).to be_nil # It doesn't even create it
        end
      end
    end

    it "calls the EnvironmentLogger" do
      expect(Datadog::Profiling::Component).to receive(:build_profiler_component)
        .and_return([nil, environment_logger_extra])

      expect(Datadog::Core::Diagnostics::EnvironmentLogger).to \
        receive(:collect_and_log!).with(
          environment_logger_extra.merge(dynamic_instrumentation_enabled: false),
        )

      startup!
    end

    # Always publish, even with Rails: after_initialize won't re-run on reconfiguration.
    it "calls ProcessDiscovery" do
      expect(Datadog::Core::ProcessDiscovery).to receive(:publish)
        .with(settings)

      startup!
    end

    context "when Rails::Railtie is defined" do
      before do
        stub_const("::Rails::Railtie", Class.new)
        # railtie.rb calls ActiveSupport.on_load at class-body level; stub it since ActiveSupport is not loaded here.
        stub_const("::ActiveSupport", Module.new {
          def self.on_load(*)
          end
        })
      end

      it "still calls ProcessDiscovery" do
        expect(Datadog::Core::ProcessDiscovery).to receive(:publish)
          .with(settings)

        startup!
      end
    end
  end

  describe "#after_fork" do
    subject(:after_fork) { components.after_fork }

    let(:open_feature_activation) do
      instance_double(Datadog::OpenFeature::Activation, after_fork: nil)
    end
    let(:symbol_database) do
      instance_double(Datadog::SymbolDatabase::Component, after_fork!: nil)
    end
    let(:data_streams) do
      instance_double(Datadog::DataStreams::Processor, restart_flush_thread: nil)
    end

    before do
      allow(telemetry).to receive(:after_fork)
      allow(remote).to receive(:after_fork)
      allow(Datadog::Core::ProcessDiscovery).to receive(:after_fork)
      allow(Datadog::OpenFeature::Activation).to receive(:new).and_return(open_feature_activation)
      allow(components).to receive(:symbol_database).and_return(symbol_database)
      allow(components).to receive(:data_streams).and_return(data_streams)
    end

    it "dispatches after_fork to OpenFeature activation" do
      after_fork

      expect(open_feature_activation).to have_received(:after_fork).once
    end

    it "dispatches after_fork to the tracer when supported" do
      tracer = instance_double(Datadog::Tracing::Tracer)
      allow(components).to receive(:tracer).and_return(tracer)
      expect(tracer).to receive(:after_fork)

      after_fork
    end

    it "dispatches after_fork! to the symbol_database when present" do
      expect(symbol_database).to receive(:after_fork!)

      after_fork
    end

    it "does not raise when symbol_database is nil" do
      allow(components).to receive(:symbol_database).and_return(nil)

      expect { after_fork }.not_to raise_error
    end

    it "dispatches restart_flush_thread to the data_streams processor when present" do
      expect(data_streams).to receive(:restart_flush_thread)

      after_fork
    end

    it "does not raise when data_streams is nil" do
      allow(components).to receive(:data_streams).and_return(nil)

      expect { after_fork }.not_to raise_error
    end
  end

  describe "#state" do
    # When Datadog.configure rebuilds the tree, the old tree's #state is read
    # by the new tree's #startup! to decide whether to restart DI.

    context "when the component reports it is implicitly enabled" do
      let(:stub_di_component) do
        instance_double(Datadog::DI::Component, implicitly_enabled?: true, shutdown!: nil, rc_enablement_signal_paths: [])
      end

      before do
        allow(Datadog::DI::Component).to receive(:build).and_return(stub_di_component)
      end

      it "captures di_implicitly_enabled? as true" do
        expect(components.state.di_implicitly_enabled?).to be true
      end
    end

    context "when the component reports it is not implicitly enabled" do
      let(:stub_di_component) do
        instance_double(Datadog::DI::Component, implicitly_enabled?: false, shutdown!: nil, rc_enablement_signal_paths: [])
      end

      before do
        allow(Datadog::DI::Component).to receive(:build).and_return(stub_di_component)
      end

      it "captures di_implicitly_enabled? as false" do
        expect(components.state.di_implicitly_enabled?).to be false
      end
    end

    context "when the component holds recorded RC enable-signal paths" do
      let(:signal_path) do
        Datadog::Core::Remote::Configuration::Path.parse("datadog/1/APM_TRACING/lib_config/config")
      end
      let(:stub_di_component) do
        instance_double(
          Datadog::DI::Component,
          implicitly_enabled?: true,
          shutdown!: nil,
          rc_enablement_signal_paths: [signal_path],
        )
      end

      before do
        allow(Datadog::DI::Component).to receive(:build).and_return(stub_di_component)
      end

      it "captures rc_enablement_signal_paths from the component" do
        expect(components.state.rc_enablement_signal_paths).to eq([signal_path])
      end
    end

    context "when the DI component is nil (unsupported environment)" do
      before do
        allow(Datadog::DI::Component).to receive(:build).and_return(nil)
      end

      it "captures di_implicitly_enabled? as false" do
        expect(components.dynamic_instrumentation).to be nil
        expect(components.state.di_implicitly_enabled?).to be false
      end

      it "captures rc_enablement_signal_paths as an empty array" do
        expect(components.state.rc_enablement_signal_paths).to eq([])
      end
    end
  end

  describe "#startup! with old_state carrying DI implicit enablement" do
    # The other side of the ComponentsState round-trip: given an old_state
    # whose di_implicitly_enabled? is true, #startup! must start DI on the
    # new tree even when settings.dynamic_instrumentation.enabled is false
    # (no env var). The env-var-only path and the no-carry path are also
    # covered to make the precedence explicit.

    # Ruby 2.5 does not load di/base.rb, so Datadog::DI.activate_tracking is
    # not defined. These tests stub Component.build to return a non-nil double,
    # which makes startup! reach the DI.activate_tracking call that's normally
    # unreachable on 2.5 (Component.build returns nil there). The semantic being
    # tested (state carry-over across Components rebuild) is platform-agnostic.
    before(:all) { skip "requires Ruby >= 2.6 (DI.activate_tracking not loaded on 2.5)" if RUBY_VERSION < "2.6" }

    subject(:startup!) { components.startup!(settings, old_state: old_state) }

    # State-aware double so start!/stop! transitions show up in started?.
    # Avoids needing the real DI C extension while still exercising the
    # exact lifecycle Components#startup! drives.
    let(:di_state) { {started: false} }
    let(:stub_di_component) do
      instance_double(Datadog::DI::Component).tap do |dbl|
        allow(dbl).to receive(:started?) { di_state[:started] }
        allow(dbl).to receive(:start!) { di_state[:started] = true }
        allow(dbl).to receive(:stop!) { di_state[:started] = false }
        allow(dbl).to receive(:shutdown!) { di_state[:started] = false }
        allow(dbl).to receive(:record_rc_enablement_signal_paths)
      end
    end

    before do
      settings.dynamic_instrumentation.internal.development = true
      allow(Datadog::Profiling::Component).to receive(:build_profiler_component)
        .and_return([nil, environment_logger_extra])
      allow(Datadog::Core::Diagnostics::EnvironmentLogger).to receive(:collect_and_log!)
      allow(Datadog::Core::ProcessDiscovery).to receive(:publish)
      allow(Datadog::DI::Component).to receive(:build).and_return(stub_di_component)
      allow(Datadog::DI).to receive(:activate_tracking)
    end

    context "old_state.di_implicitly_enabled? is true, env var not set" do
      let(:old_state) do
        Datadog::Core::Configuration::ComponentsState.new(
          telemetry_enabled: true,
          remote_started: false,
          di_implicitly_enabled: true,
        )
      end

      it "starts the DI component on the new tree" do
        expect(components.dynamic_instrumentation).not_to be_nil
        expect(components.dynamic_instrumentation.started?).to be false
        startup!
        expect(components.dynamic_instrumentation.started?).to be true
      end
    end

    context "old_state.di_implicitly_enabled? is false, env var not set" do
      let(:old_state) do
        Datadog::Core::Configuration::ComponentsState.new(
          telemetry_enabled: true,
          remote_started: false,
          di_implicitly_enabled: false,
        )
      end

      it "leaves the DI component stopped on the new tree" do
        startup!
        expect(components.dynamic_instrumentation.started?).to be false
      end
    end

    context "old_state.di_implicitly_enabled? is false, env var explicitly true" do
      let(:old_state) do
        Datadog::Core::Configuration::ComponentsState.new(
          telemetry_enabled: true,
          remote_started: false,
          di_implicitly_enabled: false,
        )
      end

      before { settings.dynamic_instrumentation.enabled = true }

      it "starts the DI component on the new tree (env-var path)" do
        startup!
        expect(components.dynamic_instrumentation.started?).to be true
      end
    end

    context "no old_state (initial startup)" do
      let(:old_state) { nil }

      it "leaves the DI component stopped when env var is not set" do
        startup!
        expect(components.dynamic_instrumentation.started?).to be false
      end

      it "does not overwrite the component's recorded signal paths" do
        expect(components.dynamic_instrumentation).not_to receive(:record_rc_enablement_signal_paths)

        startup!
      end
    end

    context "old_state carries recorded RC enable-signal paths" do
      let(:signal_path) do
        Datadog::Core::Remote::Configuration::Path.parse("datadog/1/APM_TRACING/lib_config/config")
      end
      let(:old_state) do
        Datadog::Core::Configuration::ComponentsState.new(
          telemetry_enabled: true,
          remote_started: false,
          di_implicitly_enabled: true,
          rc_enablement_signal_paths: [signal_path],
        )
      end

      it "restores the recorded paths on the rebuilt DI component and starts it" do
        expect(components.dynamic_instrumentation).to receive(:record_rc_enablement_signal_paths).with([signal_path])

        startup!

        expect(components.dynamic_instrumentation.started?).to be true
      end
    end

    context "old_state carries recorded paths while the remote was started" do
      let(:signal_path) do
        Datadog::Core::Remote::Configuration::Path.parse("datadog/1/APM_TRACING/lib_config/config")
      end
      let(:old_state) do
        Datadog::Core::Configuration::ComponentsState.new(
          telemetry_enabled: true,
          remote_started: true,
          di_implicitly_enabled: true,
          rc_enablement_signal_paths: [signal_path],
        )
      end

      it "restores the recorded paths before the replacement remote starts" do
        expect(components.dynamic_instrumentation)
          .to receive(:record_rc_enablement_signal_paths).with([signal_path]).ordered
        expect(remote).to receive(:start).ordered

        startup!
      end
    end

    context "env var was previously true and user reconfigures with enabled=false" do
      # Round-trip the reconfigure-to-disabled scenario: a process
      # boots with DD_DYNAMIC_INSTRUMENTATION_ENABLED=true, which starts DI;
      # the user later calls Datadog.configure to explicitly disable DI. The
      # new component must NOT auto-start. The bug was that #state captured
      # any started DI as "implicitly enabled", so the new tree's #startup!
      # would OR the old (incorrectly true) implicit flag with the new
      # (explicitly false) enabled setting and start DI anyway.
      let(:old_state) do
        # Construct the state the OLD tree would have produced — env var
        # had set it to true and DI was started. Per the fixed #state, this
        # captures di_implicitly_enabled? as FALSE (start was explicit).
        Datadog::Core::Configuration::ComponentsState.new(
          telemetry_enabled: true,
          remote_started: false,
          di_implicitly_enabled: false,
        )
      end

      before { settings.dynamic_instrumentation.enabled = false }

      it "leaves the DI component stopped on the new tree" do
        startup!
        expect(components.dynamic_instrumentation.started?).to be false
      end
    end
  end

  describe "#shutdown!" do
    before do
      allow(telemetry).to receive(:emit_closing!)
    end

    subject(:shutdown!) { components.shutdown!(replacement) }

    context "given no replacement" do
      let(:replacement) { nil }

      it "shuts down all components" do
        expect(components.tracer).to receive(:shutdown!)
        expect(components.remote).to receive(:shutdown!) unless components.remote.nil?
        expect(components.profiler).to receive(:shutdown!) unless components.profiler.nil?
        expect(components.dynamic_instrumentation).to receive(:shutdown!) unless components.dynamic_instrumentation.nil?
        expect(components.symbol_database).to receive(:shutdown!) unless components.symbol_database.nil?
        expect(components.appsec).to receive(:shutdown!) unless components.appsec.nil?
        expect(components.runtime_metrics).to receive(:stop)
          .with(true, close_metrics: false)
        expect(components.runtime_metrics.metrics.statsd).to receive(:close)
        expect(components.health_metrics.statsd).to receive(:close)
        expect(components.telemetry).to receive(:emit_closing!)
        expect(components.telemetry).to receive(:shutdown!)

        shutdown!
      end

      context "when OpenFeature shutdown raises" do
        let(:error) { RuntimeError.new("test failure") }
        let(:activation) do
          instance_double(Datadog::OpenFeature::Activation, shutdown!: nil)
        end

        before do
          allow(Datadog::OpenFeature::Activation).to receive(:new).and_return(activation)
          allow(activation).to receive(:shutdown!).and_raise(error)
        end

        it "reports the failure and continues library shutdown" do
          expect(components.remote).to receive(:shutdown!) unless components.remote.nil?
          expect(components.dynamic_instrumentation).to receive(:shutdown!) unless components.dynamic_instrumentation.nil?
          expect(components.symbol_database).to receive(:shutdown!) unless components.symbol_database.nil?
          expect(components.logger).to receive(:error)
            .with("Feature Flags delivery failed to shut down: RuntimeError: test failure")
          expect(telemetry).to receive(:report)
            .with(error, description: "Feature Flags delivery failed to shut down")
          expect(components.appsec).to receive(:shutdown!) unless components.appsec.nil?
          expect(components.tracer).to receive(:shutdown!)
          expect(components.profiler).to receive(:shutdown!) unless components.profiler.nil?
          expect(components.runtime_metrics).to receive(:stop)
            .with(true, close_metrics: false)
          expect(components.runtime_metrics.metrics.statsd).to receive(:close)
          expect(components.health_metrics.statsd).to receive(:close)
          expect(components.telemetry).to receive(:emit_closing!)
          expect(components.telemetry).to receive(:shutdown!)

          expect { shutdown! }.not_to raise_error
        end
      end
    end

    context "given a replacement" do
      shared_context "replacement" do
        let(:replacement) { instance_double(described_class) }
        let(:tracer) { instance_double(Datadog::Tracing::Tracer) }
        let(:profiler) { Datadog::Profiling.supported? ? instance_double(Datadog::Profiling::Profiler) : nil }
        let(:remote) { instance_double(Datadog::Core::Remote::Component) }
        let(:appsec) { instance_double(Datadog::AppSec::Component) }
        let(:dynamic_instrumentation) { instance_double(Datadog::DI::Component) }
        let(:runtime_metrics_worker) { instance_double(Datadog::Core::Workers::RuntimeMetrics, metrics: runtime_metrics) }
        let(:runtime_metrics) { instance_double(Datadog::Core::Runtime::Metrics, statsd: statsd) }
        let(:health_metrics) { instance_double(Datadog::Core::Diagnostics::Health::Metrics, statsd: statsd) }
        let(:statsd) { instance_double(::Datadog::Statsd) }

        before do
          allow(replacement).to receive(:tracer).and_return(tracer)
          allow(replacement).to receive(:profiler).and_return(profiler)
          allow(replacement).to receive(:appsec).and_return(appsec)
          allow(replacement).to receive(:dynamic_instrumentation).and_return(dynamic_instrumentation)
          allow(replacement).to receive(:remote).and_return(remote)
          allow(replacement).to receive(:runtime_metrics).and_return(runtime_metrics_worker)
          allow(replacement).to receive(:health_metrics).and_return(health_metrics)
          allow(replacement).to receive(:telemetry).and_return(telemetry)
        end
      end

      context "when no components are reused" do
        include_context "replacement"

        it "shuts down all components" do
          expect(components.tracer).to receive(:shutdown!)
          expect(components.profiler).to receive(:shutdown!) unless components.profiler.nil?
          expect(components.appsec).to receive(:shutdown!) unless components.appsec.nil?
          expect(components.dynamic_instrumentation).to receive(:shutdown!) unless components.dynamic_instrumentation.nil?
          expect(components.runtime_metrics).to receive(:stop)
            .with(true, close_metrics: false)
          expect(components.runtime_metrics.metrics.statsd).to receive(:close)
          expect(components.health_metrics.statsd).to receive(:close)
          expect(components.remote).to receive(:shutdown!)
          expect(components.telemetry).to receive(:shutdown!)

          shutdown!
        end

        context "and Statsd is not initialized" do
          before do
            allow(components.runtime_metrics.metrics)
              .to receive(:statsd)
              .and_return(nil)
          end

          it "shuts down all components" do
            expect(components.tracer).to receive(:shutdown!)
            expect(components.profiler).to receive(:shutdown!) unless components.profiler.nil?
            expect(components.runtime_metrics).to receive(:stop)
              .with(true, close_metrics: false)
            expect(components.health_metrics.statsd).to receive(:close)
            expect(components.remote).to receive(:shutdown!)
            expect(components.telemetry).to receive(:shutdown!)

            shutdown!
          end
        end
      end

      context "when the tracer is re-used" do
        include_context "replacement" do
          let(:tracer) { components.tracer }
        end

        it "shuts down all components but the tracer" do
          expect(components.tracer).to_not receive(:shutdown!)
          expect(components.profiler).to receive(:shutdown!) unless components.profiler.nil?
          expect(components.runtime_metrics).to receive(:stop)
            .with(true, close_metrics: false)
          expect(components.runtime_metrics.metrics.statsd).to receive(:close)
          expect(components.health_metrics.statsd).to receive(:close)
          expect(components.remote).to receive(:shutdown!)
          expect(components.telemetry).to receive(:shutdown!)

          shutdown!
        end
      end

      context "when one of Statsd instances are reused" do
        include_context "replacement" do
          let(:runtime_metrics_worker) { components.runtime_metrics }
        end

        it "shuts down all components but the tracer" do
          expect(components.tracer).to receive(:shutdown!)
          expect(components.profiler).to receive(:shutdown!) unless components.profiler.nil?
          expect(components.runtime_metrics).to receive(:stop)
            .with(true, close_metrics: false)
          expect(components.runtime_metrics.metrics.statsd).to_not receive(:close)
          expect(components.health_metrics.statsd).to receive(:close)
          expect(components.remote).to receive(:shutdown!)
          expect(components.telemetry).to receive(:shutdown!)

          shutdown!
        end
      end

      context "when both Statsd instances are reused" do
        include_context "replacement" do
          let(:runtime_metrics_worker) { components.runtime_metrics }
          let(:health_metrics) { components.health_metrics }
        end

        it "shuts down all components but the tracer" do
          expect(components.tracer).to receive(:shutdown!)
          expect(components.profiler).to receive(:shutdown!) unless components.profiler.nil?
          expect(components.runtime_metrics).to receive(:stop)
            .with(true, close_metrics: false)
          expect(components.runtime_metrics.metrics.statsd).to_not receive(:close)
          expect(components.health_metrics.statsd).to_not receive(:close)
          expect(components.remote).to receive(:shutdown!)
          expect(components.telemetry).to receive(:shutdown!)

          shutdown!
        end
      end
    end
  end

  describe "PATCH_ONLY_ONCE monkey patches" do
    reset_at_fork_monkey_patch_for_components!

    before do
      skip "Fork not supported" unless Process.respond_to?(:fork)
      skip "Process.spawn not supported" unless Process.respond_to?(:spawn)
    end

    it "applies AtForkMonkeyPatch and SpawnMonkeyPatch when Components is initialized" do
      expect_in_fork do
        described_class.new(Datadog::Core::Configuration::Settings.new)

        expect(Process.singleton_class.ancestors).to include(
          Datadog::Core::Utils::AtForkMonkeyPatch::ProcessMonkeyPatch,
        )
        expect(Process.singleton_class.ancestors).to include(
          Datadog::Core::Utils::SpawnMonkeyPatch::ProcessSpawnPatch,
        )
      end
    end
  end
end
