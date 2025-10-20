require 'spec_helper'
require 'datadog/di/spec_helper'
require 'datadog/profiling/spec_helper'

require 'logger'

require 'datadog/core/configuration/components'
require 'datadog/core/diagnostics/environment_logger'
require 'datadog/core/diagnostics/health'
require 'datadog/core/logger'
require 'datadog/core/telemetry/component'
require 'datadog/core/runtime/metrics'
require 'datadog/core/workers/runtime_metrics'
require 'datadog/statsd'
require 'datadog/core/configuration/agent_settings_resolver'
require 'datadog/core/transport/http/adapters/net'
require 'datadog/tracing/tracer'

# TODO: Components contains behavior for all of the different products.
#       Test behavior needs to be extracted to complimentary component files for every product.
RSpec.describe Datadog::Core::Configuration::Components do
  subject(:components) { described_class.new(settings) }

  let(:logger) do
    instance_double(Datadog::Core::Logger).tap do |logger|
      allow(logger).to receive(:debug)
    end
  end
  let(:settings) { Datadog::Core::Configuration::Settings.new }
  let(:agent_settings) { Datadog::Core::Configuration::AgentSettingsResolver.call(settings, logger: nil) }
  let(:agent_info) { Datadog::Core::Environment::AgentInfo.new(agent_settings, logger: logger) }

  let(:profiler_setup_task) { Datadog::Profiling.supported? ? instance_double(Datadog::Profiling::Tasks::Setup) : nil }
  let(:remote) { instance_double(Datadog::Core::Remote::Component, start: nil, shutdown!: nil) }
  let(:telemetry) do
    instance_double(Datadog::Core::Telemetry::Component).tap do |telemetry|
      allow(telemetry).to receive(:start)
      allow(telemetry).to receive(:enabled).and_return(false)
    end
  end

  let(:environment_logger_extra) { {hello: 123, world: '456'} }

  include_context 'non-development execution environment'

  before do
    # Ensure the real task never gets run (so it doesn't apply our thread patches and other extensions to our test env)
    if Datadog::Profiling.supported?
      allow(Datadog::Profiling::Tasks::Setup).to receive(:new).and_return(profiler_setup_task)
    end
    allow(Datadog::Statsd).to receive(:new) { instance_double(Datadog::Statsd) }
    allow(Datadog::Core::Remote::Component).to receive(:new).and_return(remote)
    allow(Datadog::Core::Telemetry::Component).to receive(:new).and_return(telemetry)
  end

  around do |example|
    ClimateControl.modify('DD_REMOTE_CONFIGURATION_ENABLED' => nil) { example.run }
  end

  describe '::new' do
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

      crashtracker = double('crashtracker')
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

    describe '@environment_logger_extra' do
      let(:environment_logger_extra) { {} }

      let(:extra) do
        components.instance_variable_get('@environment_logger_extra')
      end

      context 'DI is not enabled' do
        it 'reports DI as disabled' do
          expect(components.dynamic_instrumentation).to be nil
          expect(extra).to eq(dynamic_instrumentation_enabled: false)
        end
      end

      context 'DI is enabled' do
        before(:all) do
          skip 'DI is disabled due to Ruby version < 2.5' if RUBY_VERSION < '2.6'
        end

        before do
          settings.dynamic_instrumentation.enabled = true
        end

        after do
          # Shutdown DI if present because it creates a background thread.
          # On JRuby DI is not present.
          components.dynamic_instrumentation&.shutdown!
        end

        context 'MRI' do
          before(:all) do
            skip 'Test requires MRI' if PlatformHelpers.jruby?
          end

          it 'reports DI as enabled' do
            expect(components.dynamic_instrumentation).to be_a(Datadog::DI::Component)
            expect(extra).to eq(dynamic_instrumentation_enabled: true)
          end
        end

        context 'JRuby' do
          before(:all) do
            skip 'Test requires JRuby' unless PlatformHelpers.jruby?
          end

          it 'reports DI as disabled' do
            expect(logger).to receive(:warn).with(/cannot enable dynamic instrumentation/)
            expect(components.dynamic_instrumentation).to be nil
            expect(extra).to eq(dynamic_instrumentation_enabled: false)
          end
        end
      end
    end
  end

  describe '::build_health_metrics' do
    subject(:build_health_metrics) { described_class.build_health_metrics(settings, logger, telemetry) }

    context 'given settings' do
      shared_examples_for 'new health metrics' do
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

      context 'by default' do
        it_behaves_like 'new health metrics'
      end

      context 'with :enabled' do
        let(:enabled) { double('enabled') }

        before do
          allow(settings.health_metrics)
            .to receive(:enabled)
            .and_return(enabled)
        end

        it_behaves_like 'new health metrics' do
          let(:options) { {enabled: enabled} }
        end
      end

      context 'with :statsd' do
        let(:statsd) { instance_double(Datadog::Statsd) }

        before do
          allow(settings.health_metrics)
            .to receive(:statsd)
            .and_return(statsd)
        end

        it_behaves_like 'new health metrics' do
          let(:options) { {statsd: statsd} }
        end
      end
    end
  end

  describe '::build_logger' do
    subject(:build_logger) { described_class.build_logger(settings) }

    context 'given an instance' do
      let(:instance) { instance_double(Datadog::Core::Logger) }

      before do
        expect(settings.logger).to receive(:instance)
          .and_return(instance)

        expect(instance).to receive(:level=)
          .with(settings.logger.level)
      end

      it 'uses the logger instance' do
        expect(Datadog::Core::Logger).to_not receive(:new)
        is_expected.to be(instance)
      end
    end

    context 'given settings' do
      shared_examples_for 'new logger' do
        let(:logger) { instance_double(Datadog::Core::Logger) }
        let(:level) { settings.logger.level }

        before do
          expect(Datadog::Core::Logger).to receive(:new)
            .with($stdout)
            .and_return(logger)

          expect(logger).to receive(:level=).with(level)
        end

        it { is_expected.to be(logger) }
      end

      context 'by default' do
        it_behaves_like 'new logger'
      end

      context 'with :level' do
        let(:level) { double('level') }

        before do
          allow(settings.logger)
            .to receive(:level)
            .and_return(level)
        end

        it_behaves_like 'new logger'
      end

      context 'with debug: true' do
        before { settings.diagnostics.debug = true }

        it_behaves_like 'new logger' do
          let(:level) { ::Logger::DEBUG }
        end

        context 'and a conflicting log level' do
          before do
            allow(settings.logger)
              .to receive(:level)
              .and_return(::Logger::INFO)
          end

          it_behaves_like 'new logger' do
            let(:level) { ::Logger::DEBUG }
          end
        end
      end
    end
  end

  describe '::build_telemetry' do
    subject(:build_telemetry) { described_class.build_telemetry(settings, agent_settings, logger) }
    let(:logger) { instance_double(Logger) }

    it 'invokes Telemetry::Component.build' do
      expect(Datadog::Core::Telemetry::Component).to receive(:build).with(settings, agent_settings, logger)
      build_telemetry
    end
  end

  describe '::build_runtime_metrics' do
    subject(:build_runtime_metrics) { described_class.build_runtime_metrics(settings, logger, telemetry) }

    context 'given settings' do
      shared_examples_for 'new runtime metrics' do
        let(:runtime_metrics) { instance_double(Datadog::Core::Runtime::Metrics) }
        let(:default_options) do
          {enabled: settings.runtime_metrics.enabled,
           services: [settings.service],
           experimental_runtime_id_enabled: settings.runtime_metrics.experimental_runtime_id_enabled,}
        end
        let(:options) { {} }

        before do
          expect(Datadog::Core::Runtime::Metrics).to receive(:new)
            .with(**default_options.merge(options).merge(logger: logger, telemetry: telemetry))
            .and_return(runtime_metrics)
        end

        it { is_expected.to be(runtime_metrics) }
      end

      context 'by default' do
        it_behaves_like 'new runtime metrics'
      end

      context 'with :enabled' do
        let(:enabled) { double('enabled') }

        before do
          allow(settings.runtime_metrics)
            .to receive(:enabled)
            .and_return(enabled)
        end

        it_behaves_like 'new runtime metrics' do
          let(:options) { {enabled: enabled} }
        end
      end

      context 'with :service' do
        let(:service) { double('service') }

        before do
          allow(settings)
            .to receive(:service)
            .and_return(service)
        end

        it_behaves_like 'new runtime metrics' do
          let(:options) { {services: [service]} }
        end
      end

      context 'with :statsd' do
        let(:statsd) { instance_double(::Datadog::Statsd) }

        before do
          allow(settings.runtime_metrics)
            .to receive(:statsd)
            .and_return(statsd)
        end

        it_behaves_like 'new runtime metrics' do
          let(:options) { {statsd: statsd} }
        end
      end

      context 'with :experimental_runtime_id_enabled' do
        let(:experimental_runtime_id_enabled) { double('experimental_runtime_id_enabled') }

        before do
          allow(settings.runtime_metrics)
            .to receive(:experimental_runtime_id_enabled)
            .and_return(experimental_runtime_id_enabled)
        end

        it_behaves_like 'new runtime metrics' do
          let(:options) { {experimental_runtime_id_enabled: experimental_runtime_id_enabled} }
        end
      end
    end
  end

  describe '::build_runtime_metrics_worker' do
    subject(:build_runtime_metrics_worker) { described_class.build_runtime_metrics_worker(settings, logger, telemetry) }

    context 'given settings' do
      shared_examples_for 'new runtime metrics worker' do
        let(:runtime_metrics_worker) { instance_double(Datadog::Core::Workers::RuntimeMetrics) }
        let(:runtime_metrics) { instance_double(Datadog::Core::Runtime::Metrics) }
        let(:default_options) do
          {
            enabled: settings.runtime_metrics.enabled,
            metrics: runtime_metrics
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

      context 'by default' do
        it_behaves_like 'new runtime metrics worker'
      end

      context 'with :enabled' do
        let(:enabled) { double('enabled') }

        before do
          allow(settings.runtime_metrics)
            .to receive(:enabled)
            .and_return(enabled)
        end

        it_behaves_like 'new runtime metrics worker' do
          let(:options) { {enabled: enabled} }
        end
      end

      context 'with :opts' do
        let(:opts) { {custom_option: :custom_value} }

        before do
          allow(settings.runtime_metrics)
            .to receive(:opts)
            .and_return(opts)
        end

        it_behaves_like 'new runtime metrics worker' do
          let(:options) { opts }
        end
      end
    end
  end

  describe '#reconfigure_sampler' do
    subject(:reconfigure_sampler) { components.reconfigure_sampler }

    context 'with configuration changes' do
      before do
        Datadog.configuration.tracing.sampling.rate_limit = 123
      end

      it 'does not change the sampler delegator object' do
        expect { reconfigure_sampler }.to_not(change { components.tracer.sampler })
      end

      it "changes the sampler delegator's delegatee" do
        expect { reconfigure_sampler }.to(
          change do
            components.tracer.sampler.sampler.priority_sampler.rate_limiter.rate
          end.from(100).to(123)
        )
      end
    end
  end

  describe '#startup!' do
    subject(:startup!) { components.startup!(settings) }

    context 'when profiling' do
      context 'is unsupported' do
        before do
          allow(Datadog::Profiling)
            .to receive(:unsupported_reason)
            .and_return('Disabled for testing')
        end

        context 'and enabled' do
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

        context 'and disabled' do
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

      context 'is enabled' do
        # Using a generic double rather than instance_double since if profiling is not supported by the
        # current CI runner we won't even load the Datadog::Profiling::Profiler class.
        let(:profiler) { instance_double('Datadog::Profiling::Profiler') }

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

    context 'with remote' do
      shared_context 'stub remote configuration agent response' do
        before do
          WebMock.enable!
          stub_request(:get, %r{/info}).to_return(body: info_response, status: 200)
          stub_request(:post, %r{/v0\.7/config}).to_return(body: '{}', status: 200)
        end

        after { WebMock.disable! }

        let(:info_response) { {endpoints: ['/v0.7/config']}.to_json }
      end

      context 'disabled' do
        before { allow(settings.remote).to receive(:enabled).and_return(false) }

        it 'does not start the remote manager' do
          startup!
          expect(components.remote).to be_nil # It doesn't even create it
        end
      end
    end

    it 'calls the EnvironmentLogger' do
      expect(Datadog::Profiling::Component).to receive(:build_profiler_component)
        .and_return([nil, environment_logger_extra])

      expect(Datadog::Core::Diagnostics::EnvironmentLogger).to \
        receive(:collect_and_log!).with(
          environment_logger_extra.merge(dynamic_instrumentation_enabled: false)
        )

      startup!
    end

    # This should stay here, not in initialize. During reconfiguration, the order of the calls is:
    # initialize new components, shutdown old components, startup new components.
    # Because this is a singleton, if we call it in initialize, it will be shutdown right away.
    it 'calls ProcessDiscovery' do
      expect(Datadog::Core::ProcessDiscovery).to receive(:publish)
        .with(settings)

      startup!
    end
  end

  describe '#shutdown!' do
    before do
      allow(telemetry).to receive(:emit_closing!)
    end

    subject(:shutdown!) { components.shutdown!(replacement) }

    context 'given no replacement' do
      let(:replacement) { nil }

      it 'shuts down all components' do
        expect(components.tracer).to receive(:shutdown!)
        expect(components.remote).to receive(:shutdown!) unless components.remote.nil?
        expect(components.profiler).to receive(:shutdown!) unless components.profiler.nil?
        expect(components.dynamic_instrumentation).to receive(:shutdown!) unless components.dynamic_instrumentation.nil?
        expect(components.appsec).to receive(:shutdown!) unless components.appsec.nil?
        expect(components.runtime_metrics).to receive(:stop)
          .with(true, close_metrics: false)
        expect(components.runtime_metrics.metrics.statsd).to receive(:close)
        expect(components.health_metrics.statsd).to receive(:close)
        expect(components.telemetry).to receive(:emit_closing!)
        expect(components.telemetry).to receive(:shutdown!)

        shutdown!
      end
    end

    context 'given a replacement' do
      shared_context 'replacement' do
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

      context 'when no components are reused' do
        include_context 'replacement'

        it 'shuts down all components' do
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

        context 'and Statsd is not initialized' do
          before do
            allow(components.runtime_metrics.metrics)
              .to receive(:statsd)
              .and_return(nil)
          end

          it 'shuts down all components' do
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

      context 'when the tracer is re-used' do
        include_context 'replacement' do
          let(:tracer) { components.tracer }
        end

        it 'shuts down all components but the tracer' do
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

      context 'when one of Statsd instances are reused' do
        include_context 'replacement' do
          let(:runtime_metrics_worker) { components.runtime_metrics }
        end

        it 'shuts down all components but the tracer' do
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

      context 'when both Statsd instances are reused' do
        include_context 'replacement' do
          let(:runtime_metrics_worker) { components.runtime_metrics }
          let(:health_metrics) { components.health_metrics }
        end

        it 'shuts down all components but the tracer' do
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
end
