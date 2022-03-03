# typed: false
require 'spec_helper'
require 'datadog/profiling/spec_helper'

require 'logger'

require 'datadog/core/configuration/agent_settings_resolver'
require 'datadog/core/configuration/components'
require 'datadog/core/diagnostics/environment_logger'
require 'datadog/core/diagnostics/health'
require 'datadog/core/logger'
require 'datadog/core/runtime/metrics'
require 'datadog/core/workers/runtime_metrics'
require 'datadog/profiling'
require 'datadog/statsd'
require 'datadog/tracing/flush'
require 'datadog/tracing/sampling/all_sampler'
require 'datadog/tracing/sampling/priority_sampler'
require 'datadog/tracing/sampling/rate_by_service_sampler'
require 'datadog/tracing/sampling/rule_sampler'
require 'datadog/tracing/sync_writer'
require 'datadog/tracing/tracer'
require 'datadog/tracing/writer'
require 'ddtrace/transport/http/adapters/net'

RSpec.describe Datadog::Core::Configuration::Components do
  subject(:components) { described_class.new(settings) }

  let(:settings) { Datadog::Core::Configuration::Settings.new }

  let(:profiler_setup_task) { Datadog::Profiling.supported? ? instance_double(Datadog::Profiling::Tasks::Setup) : nil }

  before do
    # Ensure the real task never gets run (so it doesn't apply our thread patches and other extensions to our test env)
    if Datadog::Profiling.supported?
      allow(Datadog::Profiling::Tasks::Setup).to receive(:new).and_return(profiler_setup_task)
    end
    allow(Datadog::Statsd).to receive(:new) { instance_double(Datadog::Statsd) }
  end

  describe '::new' do
    let(:logger) { instance_double(Datadog::Core::Logger) }
    let(:tracer) { instance_double(Datadog::Tracing::Tracer) }
    let(:profiler) { Datadog::Profiling.supported? ? instance_double(Datadog::Profiling::Profiler) : nil }
    let(:runtime_metrics) { instance_double(Datadog::Core::Workers::RuntimeMetrics) }
    let(:health_metrics) { instance_double(Datadog::Core::Diagnostics::Health::Metrics) }

    before do
      expect(described_class).to receive(:build_logger)
        .with(settings)
        .and_return(logger)

      expect(described_class).to receive(:build_tracer)
        .with(settings, instance_of(Datadog::Core::Configuration::AgentSettingsResolver::AgentSettings))
        .and_return(tracer)

      expect(described_class).to receive(:build_profiler)
        .with(
          settings,
          instance_of(Datadog::Core::Configuration::AgentSettingsResolver::AgentSettings),
          tracer
        )
        .and_return(profiler)

      expect(described_class).to receive(:build_runtime_metrics_worker)
        .with(settings)
        .and_return(runtime_metrics)

      expect(described_class).to receive(:build_health_metrics)
        .with(settings)
        .and_return(health_metrics)
    end

    it do
      expect(components.logger).to be logger
      expect(components.tracer).to be tracer
      expect(components.profiler).to be profiler
      expect(components.runtime_metrics).to be runtime_metrics
      expect(components.health_metrics).to be health_metrics
    end
  end

  describe '::build_health_metrics' do
    subject(:build_health_metrics) { described_class.build_health_metrics(settings) }

    context 'given settings' do
      shared_examples_for 'new health metrics' do
        let(:health_metrics) { instance_double(Datadog::Core::Diagnostics::Health::Metrics) }
        let(:default_options) { { enabled: settings.diagnostics.health_metrics.enabled } }
        let(:options) { {} }

        before do
          expect(Datadog::Core::Diagnostics::Health::Metrics).to receive(:new)
            .with(default_options.merge(options))
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
          allow(settings.diagnostics.health_metrics)
            .to receive(:enabled)
            .and_return(enabled)
        end

        it_behaves_like 'new health metrics' do
          let(:options) { { enabled: enabled } }
        end
      end

      context 'with :statsd' do
        let(:statsd) { instance_double(Datadog::Statsd) }

        before do
          allow(settings.diagnostics.health_metrics)
            .to receive(:statsd)
            .and_return(statsd)
        end

        it_behaves_like 'new health metrics' do
          let(:options) { { statsd: statsd } }
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

  describe '::build_runtime_metrics' do
    subject(:build_runtime_metrics) { described_class.build_runtime_metrics(settings) }

    context 'given settings' do
      shared_examples_for 'new runtime metrics' do
        let(:runtime_metrics) { instance_double(Datadog::Core::Runtime::Metrics) }
        let(:default_options) { { enabled: settings.runtime_metrics.enabled, services: [settings.service] } }
        let(:options) { {} }

        before do
          expect(Datadog::Core::Runtime::Metrics).to receive(:new)
            .with(default_options.merge(options))
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
          let(:options) { { enabled: enabled } }
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
          let(:options) { { services: [service] } }
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
          let(:options) { { statsd: statsd } }
        end
      end
    end
  end

  describe '::build_runtime_metrics_worker' do
    subject(:build_runtime_metrics_worker) { described_class.build_runtime_metrics_worker(settings) }

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
            .with(settings)
            .and_return(runtime_metrics)

          expect(Datadog::Core::Workers::RuntimeMetrics).to receive(:new)
            .with(default_options.merge(options))
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
          let(:options) { { enabled: enabled } }
        end
      end

      context 'with :opts' do
        let(:opts) { { custom_option: :custom_value } }

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

  describe '::build_tracer' do
    let(:agent_settings) { Datadog::Core::Configuration::AgentSettingsResolver.call(settings, logger: nil) }

    subject(:build_tracer) { described_class.build_tracer(settings, agent_settings) }

    context 'given an instance' do
      let(:instance) { instance_double(Datadog::Tracing::Tracer) }

      before do
        expect(settings.tracing).to receive(:instance)
          .and_return(instance)
      end

      it 'uses the tracer instance' do
        expect(Datadog::Tracing::Tracer).to_not receive(:new)
        is_expected.to be(instance)
      end
    end

    context 'given settings' do
      shared_examples_for 'new tracer' do
        let(:tracer) { instance_double(Datadog::Tracing::Tracer) }
        let(:writer) { Datadog::Tracing::Writer.new }
        let(:trace_flush) { be_a(Datadog::Tracing::Flush::Finished) }
        let(:sampler) do
          if defined?(super)
            super()
          else
            lambda do |sampler|
              expect(sampler).to be_a(Datadog::Tracing::Sampling::PrioritySampler)
              expect(sampler.pre_sampler).to be_a(Datadog::Tracing::Sampling::AllSampler)
              expect(sampler.priority_sampler.rate_limiter.rate).to eq(settings.tracing.sampling.rate_limit)
              expect(sampler.priority_sampler.default_sampler).to be_a(Datadog::Tracing::Sampling::RateByServiceSampler)
            end
          end
        end
        let(:default_options) do
          {
            default_service: settings.service,
            enabled: settings.tracing.enabled,
            trace_flush: trace_flush,
            tags: settings.tags,
            sampler: sampler,
            writer: writer,
          }
        end

        let(:options) { defined?(super) ? super() : {} }
        let(:tracer_options) { default_options.merge(options) }
        let(:writer_options) { defined?(super) ? super() : {} }

        before do
          expect(Datadog::Tracing::Tracer).to receive(:new)
            .with(tracer_options)
            .and_return(tracer)

          allow(Datadog::Tracing::Writer).to receive(:new)
            .with(agent_settings: agent_settings, **writer_options)
            .and_return(writer)
        end

        after do
          writer.stop
        end

        it { is_expected.to be(tracer) }
      end

      shared_examples 'event publishing writer' do
        it 'subscribes to writer events' do
          expect(writer.events.after_send).to receive(:subscribe) do |&block|
            expect(block)
              .to be(
                Datadog::Core::Configuration::Components
                  .singleton_class::WRITER_RECORD_ENVIRONMENT_INFORMATION_CALLBACK
              )
          end

          build_tracer
        end
      end

      shared_examples 'event publishing writer and priority sampler' do
        it_behaves_like 'event publishing writer'

        before do
          allow(writer.events.after_send).to receive(:subscribe)
        end

        let(:sampler_rates_callback) { -> { double('sampler rates callback') } }

        it 'subscribes to writer events' do
          expect(described_class).to receive(:writer_update_priority_sampler_rates_callback)
            .with(tracer_options[:sampler]).and_return(sampler_rates_callback)

          expect(writer.events.after_send).to receive(:subscribe) do |&block|
            expect(block)
              .to be(Datadog::Core::Configuration::Components
                       .singleton_class::WRITER_RECORD_ENVIRONMENT_INFORMATION_CALLBACK)
          end

          expect(writer.events.after_send).to receive(:subscribe) do |&block|
            expect(block).to be(sampler_rates_callback)
          end
          build_tracer
        end
      end

      context 'by default' do
        it_behaves_like 'new tracer' do
          it_behaves_like 'event publishing writer and priority sampler'
        end
      end

      context 'with :enabled' do
        let(:enabled) { double('enabled') }

        before do
          allow(settings.tracing)
            .to receive(:enabled)
            .and_return(enabled)
        end

        it_behaves_like 'new tracer' do
          let(:options) { { enabled: enabled } }
          it_behaves_like 'event publishing writer and priority sampler'
        end
      end

      context 'with :env' do
        let(:env) { double('env') }

        before do
          allow(settings)
            .to receive(:env)
            .and_return(env)
        end

        it_behaves_like 'new tracer' do
          let(:options) { { tags: { 'env' => env } } }
          it_behaves_like 'event publishing writer and priority sampler'
        end
      end

      context 'with :partial_flush :enabled' do
        let(:enabled) { true }

        before do
          allow(settings.tracing.partial_flush)
            .to receive(:enabled)
            .and_return(enabled)
        end

        it_behaves_like 'new tracer' do
          let(:options) { { trace_flush: be_a(Datadog::Tracing::Flush::Partial) } }
          it_behaves_like 'event publishing writer and priority sampler'
        end

        context 'with :partial_flush :min_spans_threshold' do
          let(:min_spans_threshold) { double('min_spans_threshold') }

          before do
            allow(settings.tracing.partial_flush)
              .to receive(:min_spans_threshold)
              .and_return(min_spans_threshold)
          end

          it_behaves_like 'new tracer' do
            let(:options) do
              { trace_flush: be_a(Datadog::Tracing::Flush::Partial) &
                have_attributes(min_spans_for_partial: min_spans_threshold) }
            end

            it_behaves_like 'event publishing writer and priority sampler'
          end
        end
      end

      context 'with :priority_sampling' do
        before do
          allow(settings.tracing)
            .to receive(:priority_sampling)
            .and_return(priority_sampling)
        end

        context 'enabled' do
          let(:priority_sampling) { true }

          it_behaves_like 'new tracer'

          context 'with :sampler' do
            before do
              allow(settings.tracing)
                .to receive(:sampler)
                .and_return(sampler)
            end

            context 'that is a priority sampler' do
              let(:sampler) { Datadog::Tracing::Sampling::PrioritySampler.new }

              it_behaves_like 'new tracer' do
                let(:options) { { sampler: sampler } }
                it_behaves_like 'event publishing writer and priority sampler'
              end
            end

            context 'that is not a priority sampler' do
              let(:sampler) { double('sampler') }

              context 'wraps sampler in a priority sampler' do
                it_behaves_like 'new tracer' do
                  let(:options) do
                    { sampler: be_a(Datadog::Tracing::Sampling::PrioritySampler) & have_attributes(
                      pre_sampler: sampler,
                      priority_sampler: be_a(Datadog::Tracing::Sampling::RuleSampler)
                    ) }
                  end

                  it_behaves_like 'event publishing writer and priority sampler'
                end
              end
            end
          end
        end

        context 'disabled' do
          let(:priority_sampling) { false }

          it_behaves_like 'new tracer' do
            let(:options) { { sampler: be_a(Datadog::Tracing::Sampling::RuleSampler) } }
          end

          context 'with :sampler' do
            before do
              allow(settings.tracing)
                .to receive(:sampler)
                .and_return(sampler)
            end

            let(:sampler) { double('sampler') }

            it_behaves_like 'new tracer' do
              let(:options) { { sampler: sampler } }
              it_behaves_like 'event publishing writer'
            end
          end
        end
      end

      context 'with :service' do
        let(:service) { double('service') }

        before do
          allow(settings)
            .to receive(:service)
            .and_return(service)
        end

        it_behaves_like 'new tracer' do
          let(:options) { { default_service: service } }
          it_behaves_like 'event publishing writer and priority sampler'
        end
      end

      context 'with :tags' do
        let(:tags) do
          {
            'env' => 'tag_env',
            'version' => 'tag_version'
          }
        end

        before do
          allow(settings)
            .to receive(:tags)
            .and_return(tags)
        end

        it_behaves_like 'new tracer' do
          let(:options) { { tags: tags } }
          it_behaves_like 'event publishing writer and priority sampler'
        end

        context 'with conflicting :env' do
          let(:env) { 'setting_env' }

          before do
            allow(settings)
              .to receive(:env)
              .and_return(env)
          end

          it_behaves_like 'new tracer' do
            let(:options) { { tags: tags.merge('env' => env) } }
            it_behaves_like 'event publishing writer and priority sampler'
          end
        end

        context 'with conflicting :version' do
          let(:version) { 'setting_version' }

          before do
            allow(settings)
              .to receive(:version)
              .and_return(version)
          end

          it_behaves_like 'new tracer' do
            let(:options) { { tags: tags.merge('version' => version) } }
            it_behaves_like 'event publishing writer and priority sampler'
          end
        end
      end

      context 'with :test_mode' do
        let(:sampler) do
          lambda do |sampler|
            expect(sampler).to be_a(Datadog::Tracing::Sampling::PrioritySampler)
            expect(sampler.pre_sampler).to be_a(Datadog::Tracing::Sampling::AllSampler)
            expect(sampler.priority_sampler).to be_a(Datadog::Tracing::Sampling::AllSampler)
          end
        end

        context ':enabled' do
          before do
            allow(settings.tracing.test_mode)
              .to receive(:enabled)
              .and_return(enabled)
          end

          context 'set to true' do
            let(:enabled) { true }
            let(:sync_writer) { Datadog::Tracing::SyncWriter.new }

            before do
              expect(Datadog::Tracing::SyncWriter)
                .to receive(:new)
                .with(agent_settings: agent_settings, **writer_options)
                .and_return(writer)
            end

            context 'and :trace_flush' do
              before do
                allow(settings.tracing.test_mode)
                  .to receive(:trace_flush)
                  .and_return(trace_flush)
              end

              context 'is not set' do
                let(:trace_flush) { nil }

                it_behaves_like 'new tracer' do
                  let(:options) do
                    {
                      writer: kind_of(Datadog::Tracing::SyncWriter)
                    }
                  end
                  let(:writer) { sync_writer }

                  it_behaves_like 'event publishing writer'
                end
              end

              context 'is set' do
                let(:trace_flush) { instance_double(Datadog::Tracing::Flush::Finished) }

                it_behaves_like 'new tracer' do
                  let(:options) do
                    {
                      trace_flush: trace_flush,
                      writer: kind_of(Datadog::Tracing::SyncWriter)
                    }
                  end
                  let(:writer) { sync_writer }

                  it_behaves_like 'event publishing writer'
                end
              end
            end

            context 'and :writer_options' do
              before do
                allow(settings.tracing.test_mode)
                  .to receive(:writer_options)
                  .and_return(writer_options)
              end

              context 'are set' do
                let(:writer_options) { { transport_options: :bar } }

                it_behaves_like 'new tracer' do
                  let(:options) do
                    {
                      writer: writer
                    }
                  end
                  let(:writer) { sync_writer }

                  it_behaves_like 'event publishing writer'
                end
              end
            end
          end
        end
      end

      context 'with :version' do
        let(:version) { double('version') }

        before do
          allow(settings)
            .to receive(:version)
            .and_return(version)
        end

        it_behaves_like 'new tracer' do
          let(:options) { { tags: { 'version' => version } } }
        end
      end

      context 'with :writer' do
        let(:writer) { instance_double(Datadog::Tracing::Writer) }

        before do
          allow(settings.tracing)
            .to receive(:writer)
            .and_return(writer)

          expect(Datadog::Tracing::Writer).to_not receive(:new)
        end

        it_behaves_like 'new tracer' do
          let(:options) { { writer: writer } }
        end

        context 'that publishes events' do
          it_behaves_like 'new tracer' do
            let(:options) { { writer: writer } }
            let(:writer) { Datadog::Tracing::Writer.new }
            after { writer.stop }

            it_behaves_like 'event publishing writer and priority sampler'
          end
        end
      end

      context 'with :writer_options' do
        let(:writer_options) { { custom_option: :custom_value } }

        it_behaves_like 'new tracer' do
          before do
            expect(settings.tracing)
              .to receive(:writer_options)
              .and_return(writer_options)
          end
        end

        context 'and :writer' do
          let(:writer) { double('writer') }

          before do
            allow(settings.tracing)
              .to receive(:writer)
              .and_return(writer)
          end

          it_behaves_like 'new tracer' do
            # Ignores the writer options in favor of the writer
            let(:options) { { writer: writer } }
          end
        end
      end
    end
  end

  describe 'writer event callbacks' do
    describe Datadog::Core::Configuration::Components.singleton_class::WRITER_RECORD_ENVIRONMENT_INFORMATION_CALLBACK do
      subject(:call) { described_class.call(writer, responses) }
      let(:writer) { double('writer') }
      let(:responses) { [double('response')] }

      it 'invokes the environment logger with responses' do
        expect(Datadog::Core::Diagnostics::EnvironmentLogger).to receive(:log!).with(responses)
        call
      end
    end

    describe '.writer_update_priority_sampler_rates_callback' do
      subject(:call) do
        described_class.writer_update_priority_sampler_rates_callback(sampler).call(writer, responses)
      end

      let(:sampler) { double('sampler') }
      let(:writer) { double('writer') }
      let(:responses) do
        [
          double('first response'),
          double('last response', internal_error?: internal_error, service_rates: service_rates),
        ]
      end

      let(:service_rates) { nil }

      context 'with a successful response' do
        let(:internal_error) { false }

        context 'with service rates returned by response' do
          let(:service_rates) { double('service rates') }

          it 'updates sampler with service rates' do
            expect(sampler).to receive(:update).with(service_rates)
            call
          end
        end

        context 'without service rates returned by response' do
          it 'does not update sampler' do
            expect(sampler).to_not receive(:update)
            call
          end
        end
      end

      context 'with an internal error response' do
        let(:internal_error) { true }

        it 'does not update sampler' do
          expect(sampler).to_not receive(:update)
          call
        end
      end
    end
  end

  describe '::build_profiler' do
    let(:agent_settings) { Datadog::Core::Configuration::AgentSettingsResolver.call(settings, logger: nil) }
    let(:profiler) { build_profiler }
    let(:tracer) { instance_double(Datadog::Tracing::Tracer) }

    subject(:build_profiler) { described_class.build_profiler(settings, agent_settings, tracer) }

    context 'when profiling is not supported' do
      before { allow(Datadog::Profiling).to receive(:supported?).and_return(false) }

      it { is_expected.to be nil }
    end

    context 'given settings' do
      before { skip_if_profiling_not_supported(self) }

      shared_examples_for 'disabled profiler' do
        it { is_expected.to be nil }
      end

      shared_context 'enabled profiler' do
        before do
          allow(settings.profiling)
            .to receive(:enabled)
            .and_return(true)
          allow(profiler_setup_task).to receive(:run)
        end
      end

      shared_examples_for 'profiler with default collectors' do
        subject(:stack_collector) { profiler.collectors.first }

        it 'has a Stack collector' do
          expect(profiler.collectors).to have(1).item
          expect(profiler.collectors).to include(kind_of(Datadog::Profiling::Collectors::Stack))
          is_expected.to have_attributes(
            enabled?: true,
            started?: false,
            ignore_thread: nil,
            max_frames: settings.profiling.advanced.max_frames,
            max_time_usage_pct: 2.0
          )
        end
      end

      shared_examples_for 'profiler with default scheduler' do
        subject(:scheduler) { profiler.scheduler }

        it do
          is_expected.to be_a_kind_of(Datadog::Profiling::Scheduler)
          is_expected.to have_attributes(
            enabled?: true,
            started?: false,
            loop_base_interval: 60.0
          )
        end
      end

      shared_examples_for 'profiler with default recorder' do
        subject(:recorder) { profiler.scheduler.send(:recorder) }

        it do
          is_expected.to have_attributes(max_size: settings.profiling.advanced.max_events)
        end
      end

      context 'by default' do
        it_behaves_like 'disabled profiler'
      end

      context 'with :enabled false' do
        before do
          allow(settings.profiling)
            .to receive(:enabled)
            .and_return(false)
        end

        it_behaves_like 'disabled profiler'
      end

      context 'with :enabled true' do
        include_context 'enabled profiler'

        context 'by default' do
          it_behaves_like 'profiler with default collectors'
          it_behaves_like 'profiler with default scheduler'
          it_behaves_like 'profiler with default recorder'

          it 'runs the setup task to set up any needed extensions for profiling' do
            expect(profiler_setup_task).to receive(:run)

            build_profiler
          end

          it 'builds an HttpTransport with the current settings' do
            expect(Datadog::Profiling::HttpTransport).to receive(:new).with(
              agent_settings: agent_settings,
              site: settings.site,
              api_key: settings.api_key,
              upload_timeout_seconds: settings.profiling.upload.timeout_seconds,
            )

            build_profiler
          end

          it 'creates a scheduler with an HttpTransport' do
            http_transport = instance_double(Datadog::Profiling::HttpTransport)

            expect(Datadog::Profiling::HttpTransport).to receive(:new).and_return(http_transport)

            build_profiler

            expect(profiler.scheduler.send(:transport)).to be http_transport
          end

          [true, false].each do |value|
            context "when endpoint_collection_enabled is #{value}" do
              before { settings.profiling.advanced.endpoint.collection.enabled = value }

              it "initializes the TraceIdentifiers::Helper with endpoint_collection_enabled: #{value}" do
                expect(Datadog::Profiling::TraceIdentifiers::Helper)
                  .to receive(:new).with(tracer: tracer, endpoint_collection_enabled: value)

                build_profiler
              end
            end
          end

          it 'initializes the recorder with a code provenance collector' do
            expect(Datadog::Profiling::Recorder).to receive(:new) do |*_args, code_provenance_collector:|
              expect(code_provenance_collector).to be_a_kind_of(Datadog::Profiling::Collectors::CodeProvenance)
            end.and_call_original

            build_profiler
          end

          context 'when code provenance is disabled' do
            before { settings.profiling.advanced.code_provenance_enabled = false }

            it 'initializes the recorder with a nil code provenance collector' do
              expect(Datadog::Profiling::Recorder).to receive(:new) do |*_args, code_provenance_collector:|
                expect(code_provenance_collector).to be nil
              end.and_call_original

              build_profiler
            end
          end
        end

        context 'and :transport' do
          context 'is given' do
            let(:transport) { double('Custom transport') }

            before do
              allow(settings.profiling.exporter)
                .to receive(:transport)
                .and_return(transport)
            end

            it_behaves_like 'profiler with default collectors'
            it_behaves_like 'profiler with default scheduler'
            it_behaves_like 'profiler with default recorder'

            it 'uses the custom transport' do
              expect(profiler.scheduler.send(:transport)).to be transport
            end
          end
        end
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
        before do
          skip 'Profiling not supported.' unless Datadog::Profiling.supported?

          allow(settings.profiling)
            .to receive(:enabled)
            .and_return(true)
          allow(profiler_setup_task).to receive(:run)
        end

        it do
          expect(components.profiler)
            .to receive(:start)

          startup!
        end
      end

      context 'is disabled' do
        before do
          allow(settings.profiling)
            .to receive(:enabled)
            .and_return(false)
        end

        it do
          expect(components.logger)
            .to receive(:debug)
            .with(/is disabled/)

          startup!
        end
      end
    end
  end

  describe '#shutdown!' do
    subject(:shutdown!) { components.shutdown!(replacement) }

    context 'given no replacement' do
      let(:replacement) { nil }

      it 'shuts down all components' do
        expect(components.tracer).to receive(:shutdown!)
        expect(components.profiler).to receive(:shutdown!) unless components.profiler.nil?
        expect(components.runtime_metrics).to receive(:stop)
          .with(true, close_metrics: false)
        expect(components.runtime_metrics.metrics.statsd).to receive(:close)
        expect(components.health_metrics.statsd).to receive(:close)

        shutdown!
      end
    end

    context 'given a replacement' do
      shared_context 'replacement' do
        let(:replacement) { instance_double(described_class) }
        let(:tracer) { instance_double(Datadog::Tracing::Tracer) }
        let(:profiler) { Datadog::Profiling.supported? ? instance_double(Datadog::Profiling::Profiler) : nil }
        let(:runtime_metrics_worker) { instance_double(Datadog::Core::Workers::RuntimeMetrics, metrics: runtime_metrics) }
        let(:runtime_metrics) { instance_double(Datadog::Core::Runtime::Metrics, statsd: statsd) }
        let(:health_metrics) { instance_double(Datadog::Core::Diagnostics::Health::Metrics, statsd: statsd) }
        let(:statsd) { instance_double(::Datadog::Statsd) }

        before do
          allow(replacement).to receive(:tracer).and_return(tracer)
          allow(replacement).to receive(:profiler).and_return(profiler)
          allow(replacement).to receive(:runtime_metrics).and_return(runtime_metrics_worker)
          allow(replacement).to receive(:health_metrics).and_return(health_metrics)
        end
      end

      context 'when no components are reused' do
        include_context 'replacement'

        it 'shuts down all components' do
          expect(components.tracer).to receive(:shutdown!)
          expect(components.profiler).to receive(:shutdown!) unless components.profiler.nil?
          expect(components.runtime_metrics).to receive(:stop)
            .with(true, close_metrics: false)
          expect(components.runtime_metrics.metrics.statsd).to receive(:close)
          expect(components.health_metrics.statsd).to receive(:close)

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

          shutdown!
        end
      end
    end
  end
end
