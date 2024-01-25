require 'spec_helper'
require 'datadog/profiling/spec_helper'

require 'logger'

require 'datadog/core/configuration/components'
require 'datadog/core/diagnostics/environment_logger'
require 'datadog/core/diagnostics/health'
require 'datadog/core/logger'
require 'datadog/core/telemetry/client'
require 'datadog/core/runtime/metrics'
require 'datadog/core/workers/runtime_metrics'
require 'datadog/statsd'
require 'datadog/core/configuration/agent_settings_resolver'
require 'datadog/tracing/flush'
require 'datadog/tracing/sampling/all_sampler'
require 'datadog/tracing/sampling/priority_sampler'
require 'datadog/tracing/sampling/rate_by_service_sampler'
require 'datadog/tracing/sampling/rule_sampler'
require 'datadog/tracing/sync_writer'
require 'datadog/tracing/tracer'
require 'datadog/tracing/writer'
require 'datadog/core/transport/http/adapters/net'

# TODO: Components contains behavior for all of the different products.
#       Test behavior needs to be extracted to complimentary component files for every product.
RSpec.describe Datadog::Core::Configuration::Components do
  subject(:components) { described_class.new(settings) }

  let(:logger) { instance_double(Datadog::Core::Logger) }
  let(:settings) { Datadog::Core::Configuration::Settings.new }
  let(:agent_settings) { Datadog::Core::Configuration::AgentSettingsResolver.call(settings, logger: nil) }

  let(:profiler_setup_task) { Datadog::Profiling.supported? ? instance_double(Datadog::Profiling::Tasks::Setup) : nil }
  let(:remote) { instance_double(Datadog::Core::Remote::Component, start: nil, shutdown!: nil) }
  let(:telemetry) { instance_double(Datadog::Core::Telemetry::Client) }

  include_context 'non-development execution environment'

  before do
    # Ensure the real task never gets run (so it doesn't apply our thread patches and other extensions to our test env)
    if Datadog::Profiling.supported?
      allow(Datadog::Profiling::Tasks::Setup).to receive(:new).and_return(profiler_setup_task)
    end
    allow(Datadog::Statsd).to receive(:new) { instance_double(Datadog::Statsd) }
    allow(Datadog::Core::Remote::Component).to receive(:new).and_return(remote)
    allow(Datadog::Core::Telemetry::Client).to receive(:new).and_return(telemetry)
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

      expect(described_class).to receive(:build_tracer)
        .with(settings, agent_settings, logger: logger)
        .and_return(tracer)

      expect(Datadog::Profiling::Component).to receive(:build_profiler_component).with(
        settings: settings,
        agent_settings: agent_settings,
        optional_tracer: tracer,
      ).and_return(profiler)

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
        let(:default_options) { { enabled: settings.health_metrics.enabled } }
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
          allow(settings.health_metrics)
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
          allow(settings.health_metrics)
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

  describe '::build_telemetry' do
    subject(:build_telemetry) { described_class.build_telemetry(settings, agent_settings, logger) }
    let(:logger) { instance_double(Logger) }

    context 'given settings' do
      let(:telemetry_client) { instance_double(Datadog::Core::Telemetry::Client) }
      let(:expected_options) { { enabled: enabled, heartbeat_interval_seconds: heartbeat_interval_seconds } }
      let(:enabled) { true }
      let(:heartbeat_interval_seconds) { 60 }

      before do
        expect(Datadog::Core::Telemetry::Client).to receive(:new).with(expected_options).and_return(telemetry_client)
        allow(settings.telemetry).to receive(:enabled).and_return(enabled)
      end

      it { is_expected.to be(telemetry_client) }

      context 'with :enabled true' do
        let(:enabled) { double('enabled') }

        it { is_expected.to be(telemetry_client) }

        context 'and :unix agent adapter' do
          let(:expected_options) { { enabled: false, heartbeat_interval_seconds: heartbeat_interval_seconds } }
          let(:agent_settings) do
            instance_double(Datadog::Core::Configuration::AgentSettingsResolver::AgentSettings, adapter: :unix)
          end

          it 'does not enable telemetry for unsupported non-http transport' do
            expect(logger).to receive(:debug)
            is_expected.to be(telemetry_client)
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
    subject(:build_tracer) { described_class.build_tracer(settings, agent_settings, logger: logger) }

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
        let(:span_sampler) { be_a(Datadog::Tracing::Sampling::Span::Sampler) }
        let(:default_options) do
          {
            default_service: settings.service,
            enabled: settings.tracing.enabled,
            trace_flush: trace_flush,
            tags: settings.tags,
            sampler: sampler,
            span_sampler: span_sampler,
            writer: writer,
          }
        end

        let(:options) { defined?(super) ? super() : {} }
        let(:tracer_options) do
          default_options.merge(options).tap do |options|
            sampler = options[:sampler]
            options[:sampler] = lambda do |sampler_delegator|
              expect(sampler_delegator).to be_a(Datadog::Tracing::Component::SamplerDelegatorComponent)
              expect(sampler_delegator.sampler).to match(sampler)
            end
          end
        end
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
        before do
          allow(writer.events.after_send).to receive(:subscribe)
        end

        let(:sampler_rates_callback) { -> { double('sampler rates callback') } }

        it 'subscribes to writer events' do
          expect(described_class).to receive(:writer_update_priority_sampler_rates_callback)
            .with(tracer_options[:sampler]).and_return(sampler_rates_callback)

          expect(writer.events.after_send).to receive(:subscribe) do |&block|
            expect(block)
              .to be(
                Datadog::Core::Configuration::Components
                                       .singleton_class::WRITER_RECORD_ENVIRONMENT_INFORMATION_CALLBACK
              )
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

      context 'with :sampler' do
        before do
          allow(settings.tracing)
            .to receive(:sampler)
            .and_return(sampler)
        end

        let(:sampler) { double('sampler') }

        it_behaves_like 'new tracer' do
          let(:options) { { sampler: sampler } }
          it_behaves_like 'event publishing writer and priority sampler'
        end
      end

      context 'with sampling.rules' do
        before { allow(settings.tracing.sampling).to receive(:rules).and_return(rules) }

        context 'with rules' do
          let(:rules) { '[{"sample_rate":"0.123"}]' }

          it_behaves_like 'new tracer' do
            let(:sampler) do
              lambda do |sampler|
                expect(sampler).to be_a(Datadog::Tracing::Sampling::PrioritySampler)
                expect(sampler.pre_sampler).to be_a(Datadog::Tracing::Sampling::AllSampler)

                expect(sampler.priority_sampler.rules).to have(1).item
                expect(sampler.priority_sampler.rules[0].sampler.sample_rate).to eq(0.123)
              end
            end
          end
        end
      end

      context 'with sampling.span_rules' do
        before { allow(settings.tracing.sampling).to receive(:span_rules).and_return(rules) }

        context 'with rules' do
          let(:rules) { '[{"name":"foo"}]' }

          it_behaves_like 'new tracer' do
            let(:options) do
              {
                span_sampler: be_a(Datadog::Tracing::Sampling::Span::Sampler) & have_attributes(
                  rules: [
                    Datadog::Tracing::Sampling::Span::Rule.new(
                      Datadog::Tracing::Sampling::Span::Matcher.new(name_pattern: 'foo')
                    )
                  ]
                )
              }
            end
          end
        end

        context 'without rules' do
          let(:rules) { nil }

          it_behaves_like 'new tracer' do
            let(:options) { { span_sampler: be_a(Datadog::Tracing::Sampling::Span::Sampler) & have_attributes(rules: []) } }
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

            context 'and :async' do
              context 'is set' do
                let(:writer) { Datadog::Tracing::Writer.new }
                let(:writer_options) { { transport_options: :bar } }
                let(:writer_options_test_mode) { { transport_options: :baz } }

                before do
                  allow(settings.tracing.test_mode)
                    .to receive(:async)
                    .and_return(true)

                  allow(settings.tracing.test_mode)
                    .to receive(:writer_options)
                    .and_return(writer_options_test_mode)

                  expect(Datadog::Tracing::SyncWriter)
                    .not_to receive(:new)

                  expect(Datadog::Tracing::Writer)
                    .to receive(:new)
                    .with(agent_settings: agent_settings, **writer_options_test_mode)
                    .and_return(writer)
                end

                it_behaves_like 'event publishing writer'
              end

              context 'is not set' do
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

  describe '#reconfigure_live_sampler' do
    subject(:reconfigure_live_sampler) { components.reconfigure_live_sampler }

    context 'with configuration changes' do
      before do
        Datadog.configuration.tracing.sampling.rate_limit = 123
      end

      it 'does not change the sampler delegator object' do
        expect { reconfigure_live_sampler }.to_not(change { components.tracer.sampler })
      end

      it "changes the sampler delegator's delegatee" do
        expect { reconfigure_live_sampler }.to(
          change do
            components.tracer.sampler.sampler.priority_sampler.rate_limiter.rate
          end.from(100).to(123)
        )
      end
    end
  end

  describe 'writer event callbacks' do
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

          it 'updates sampler with service rates and set decision to AGENT_RATE' do
            expect(sampler).to receive(:update).with(service_rates, decision: '-1')
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
          ).and_return(profiler)
        end

        it do
          expect(profiler).to receive(:start)

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

    context 'with remote' do
      shared_context 'stub remote configuration agent response' do
        before do
          WebMock.enable!
          stub_request(:get, %r{/info}).to_return(body: info_response, status: 200)
          stub_request(:post, %r{/v0\.7/config}).to_return(body: '{}', status: 200)
        end

        after { WebMock.disable! }

        let(:info_response) { { endpoints: ['/v0.7/config'] }.to_json }
      end

      context 'disabled' do
        before { allow(settings.remote).to receive(:enabled).and_return(false) }

        it 'does not start the remote manager' do
          startup!
          expect(components.remote).to be_nil # It doesn't even create it
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
        expect(components.remote).to receive(:shutdown!) unless components.remote.nil?
        expect(components.profiler).to receive(:shutdown!) unless components.profiler.nil?
        expect(components.appsec).to receive(:shutdown!) unless components.appsec.nil?
        expect(components.runtime_metrics).to receive(:stop)
          .with(true, close_metrics: false)
        expect(components.runtime_metrics.metrics.statsd).to receive(:close)
        expect(components.health_metrics.statsd).to receive(:close)
        expect(components.telemetry).to receive(:emit_closing!)
        expect(components.telemetry).to receive(:stop!)

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
        let(:runtime_metrics_worker) { instance_double(Datadog::Core::Workers::RuntimeMetrics, metrics: runtime_metrics) }
        let(:runtime_metrics) { instance_double(Datadog::Core::Runtime::Metrics, statsd: statsd) }
        let(:health_metrics) { instance_double(Datadog::Core::Diagnostics::Health::Metrics, statsd: statsd) }
        let(:statsd) { instance_double(::Datadog::Statsd) }
        let(:telemetry) { instance_double(Datadog::Core::Telemetry::Client) }

        before do
          allow(replacement).to receive(:tracer).and_return(tracer)
          allow(replacement).to receive(:profiler).and_return(profiler)
          allow(replacement).to receive(:appsec).and_return(appsec)
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
          expect(components.runtime_metrics).to receive(:stop)
            .with(true, close_metrics: false)
          expect(components.runtime_metrics.metrics.statsd).to receive(:close)
          expect(components.health_metrics.statsd).to receive(:close)
          expect(components.remote).to receive(:shutdown!)
          expect(components.telemetry).to receive(:stop!)

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
            expect(components.telemetry).to receive(:stop!)

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
          expect(components.telemetry).to receive(:stop!)

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
          expect(components.telemetry).to receive(:stop!)

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
          expect(components.telemetry).to receive(:stop!)

          shutdown!
        end
      end
    end
  end
end
