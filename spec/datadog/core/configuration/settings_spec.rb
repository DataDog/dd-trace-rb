require 'spec_helper'

require 'securerandom'
require 'logger'

require 'datadog/core/configuration/settings'
require 'datadog/core/environment/ext'
require 'datadog/core/runtime/ext'
require 'datadog/core/utils/time'
require 'datadog/profiling/ext'

RSpec.describe Datadog::Core::Configuration::Settings do
  subject(:settings) { described_class.new(options) }

  let(:options) { {} }

  around do |example|
    ClimateControl.modify('DD_REMOTE_CONFIGURATION_ENABLED' => nil) { example.run }
  end

  describe '#api_key' do
    subject(:api_key) { settings.api_key }

    context "when #{Datadog::Core::Environment::Ext::ENV_API_KEY}" do
      around do |example|
        ClimateControl.modify(Datadog::Core::Environment::Ext::ENV_API_KEY => api_key_env) do
          example.run
        end
      end

      context 'is not defined' do
        let(:api_key_env) { nil }

        it { is_expected.to be nil }
      end

      context 'is defined' do
        let(:api_key_env) { SecureRandom.uuid.delete('-') }

        it { is_expected.to eq(api_key_env) }
      end
    end
  end

  describe '#api_key=' do
    subject(:set_api_key) { settings.api_key = api_key }

    context 'when given a value' do
      let(:api_key) { SecureRandom.uuid.delete('-') }

      before { set_api_key }

      it { expect(settings.api_key).to eq(api_key) }
    end
  end

  describe '#diagnostics' do
    describe '#debug' do
      subject(:debug) { settings.diagnostics.debug }

      it { is_expected.to be false }

      context "when #{Datadog::Core::Configuration::Ext::Diagnostics::ENV_DEBUG_ENABLED}" do
        around do |example|
          ClimateControl.modify(Datadog::Core::Configuration::Ext::Diagnostics::ENV_DEBUG_ENABLED => environment) do
            example.run
          end
        end

        context 'is not defined' do
          let(:environment) { nil }

          it { is_expected.to be false }
        end

        context 'is set to true' do
          let(:environment) { 'true' }

          it { is_expected.to be true }
        end

        context 'is set to false' do
          let(:environment) { 'false' }

          it { is_expected.to be false }
        end
      end

      context "when #{Datadog::Core::Configuration::Ext::Diagnostics::ENV_OTEL_LOG_LEVEL}" do
        around do |example|
          ClimateControl.modify(
            {
              Datadog::Core::Configuration::Ext::Diagnostics::ENV_DEBUG_ENABLED => dd_debug_env,
              Datadog::Core::Configuration::Ext::Diagnostics::ENV_OTEL_LOG_LEVEL => otel_level_env
            }
          ) do
            example.run
          end
        end

        context 'is set to debug' do
          let(:dd_debug_env) { nil }
          let(:otel_level_env) { 'DEBUG' }

          it { is_expected.to be true }
        end

        context 'is not set to debug' do
          let(:dd_debug_env) { nil }
          let(:otel_level_env) { 'INFO' }

          it { is_expected.to be false }
        end

        context 'and DD_TRACE_DEBUG is defined' do
          let(:dd_debug_env) { 'true' }
          let(:otel_level_env) { 'info' }

          it { is_expected.to be true }
        end
      end
    end

    describe '#debug=' do
      context 'enabled' do
        subject(:set_debug) { settings.diagnostics.debug = true }

        after { settings.diagnostics.debug = false }

        it 'updates the #debug setting' do
          expect { set_debug }.to change { settings.diagnostics.debug }.from(false).to(true)
        end

        it 'requires debug dependencies' do
          expect_any_instance_of(Object).to receive(:require).with('pp')
          set_debug
        end
      end

      context 'disabled' do
        subject(:set_debug) { settings.diagnostics.debug = false }

        it 'does not require debug dependencies' do
          expect_any_instance_of(Object).to_not receive(:require)
          set_debug
        end
      end
    end
  end

  describe '#env' do
    subject(:env) { settings.env }

    context "when #{Datadog::Core::Environment::Ext::ENV_ENVIRONMENT}" do
      around do |example|
        ClimateControl.modify(Datadog::Core::Environment::Ext::ENV_ENVIRONMENT => environment) do
          example.run
        end
      end

      context 'is not defined' do
        let(:environment) { nil }

        it { is_expected.to be nil }
      end

      context 'is defined' do
        let(:environment) { 'env-value' }

        it { is_expected.to eq(environment) }
      end
    end

    context 'when an env tag is defined in DD_TAGS' do
      around do |example|
        ClimateControl.modify(Datadog::Core::Environment::Ext::ENV_TAGS => 'env:env-from-tag') do
          example.run
        end
      end

      it 'uses the env from DD_TAGS' do
        is_expected.to eq('env-from-tag')
      end

      context 'and defined via DD_ENV' do
        around do |example|
          ClimateControl.modify(Datadog::Core::Environment::Ext::ENV_ENVIRONMENT => 'env-from-dd-env') do
            example.run
          end
        end

        it 'uses the env from DD_ENV' do
          is_expected.to eq('env-from-dd-env')
        end
      end
    end
  end

  describe '#env=' do
    subject(:set_env) { settings.env = env }

    context 'when given a value' do
      let(:env) { 'custom-env' }

      before { set_env }

      it { expect(settings.env).to eq(env) }
    end

    context 'when given `nil`' do
      let(:env) { nil }

      before { set_env }

      it { expect(settings.env).to be_nil }
    end
  end

  describe '#health_metrics' do
    describe '#enabled' do
      subject(:enabled) { settings.health_metrics.enabled }

      context "when #{Datadog::Core::Configuration::Ext::Diagnostics::ENV_HEALTH_METRICS_ENABLED}" do
        around do |example|
          ClimateControl.modify(
            Datadog::Core::Configuration::Ext::Diagnostics::ENV_HEALTH_METRICS_ENABLED => environment
          ) do
            example.run
          end
        end

        context 'is not defined' do
          let(:environment) { nil }

          it { is_expected.to be false }
        end

        context 'is defined' do
          let(:environment) { 'true' }

          it { is_expected.to be true }
        end
      end
    end

    describe '#enabled=' do
      it 'changes the #enabled setting' do
        expect { settings.health_metrics.enabled = true }
          .to change { settings.health_metrics.enabled }
          .from(false)
          .to(true)
      end
    end

    describe '#statsd' do
      subject(:statsd) { settings.health_metrics.statsd }

      it { is_expected.to be nil }
    end

    describe '#statsd=' do
      let(:statsd) { double('statsd') }

      it 'changes the #statsd setting' do
        expect { settings.health_metrics.statsd = statsd }
          .to change { settings.health_metrics.statsd }
          .from(nil)
          .to(statsd)
      end
    end
  end

  describe '#logger' do
    describe '#instance' do
      subject(:instance) { settings.logger.instance }

      it { is_expected.to be nil }
    end

    describe '#instance=' do
      let(:logger) do
        double(
          :logger,
          debug: true,
          info: true,
          warn: true,
          error: true,
          level: true
        )
      end

      it 'updates the #instance setting' do
        expect { settings.logger.instance = logger }
          .to change { settings.logger.instance }
          .from(nil)
          .to(logger)
      end
    end

    describe '#level' do
      subject(:level) { settings.logger.level }

      it { is_expected.to be ::Logger::INFO }
    end

    describe 'level=' do
      let(:level) { ::Logger::DEBUG }

      it 'changes the #statsd setting' do
        expect { settings.logger.level = level }
          .to change { settings.logger.level }
          .from(::Logger::INFO)
          .to(level)
      end
    end
  end

  describe '#profiling' do
    describe '#enabled' do
      subject(:enabled) { settings.profiling.enabled }

      context "when #{Datadog::Profiling::Ext::ENV_ENABLED}" do
        around do |example|
          ClimateControl.modify(Datadog::Profiling::Ext::ENV_ENABLED => environment) do
            example.run
          end
        end

        context 'is not defined' do
          let(:environment) { nil }

          it { is_expected.to be false }
        end

        context 'is defined' do
          let(:environment) { 'true' }

          it { is_expected.to be true }
        end
      end
    end

    describe '#enabled=' do
      it 'updates the #enabled setting' do
        expect { settings.profiling.enabled = true }
          .to change { settings.profiling.enabled }
          .from(false)
          .to(true)
      end
    end

    describe '#exporter' do
      describe '#transport' do
        subject(:transport) { settings.profiling.exporter.transport }

        it { is_expected.to be nil }
      end

      describe '#transport=' do
        let(:transport) { double('transport') }

        it 'updates the #transport setting' do
          expect { settings.profiling.exporter.transport = transport }
            .to change { settings.profiling.exporter.transport }
            .from(nil)
            .to(transport)
        end
      end
    end

    describe '#allocation_enabled' do
      subject(:allocation_enabled) { settings.profiling.allocation_enabled }

      context 'when DD_PROFILING_ALLOCATION_ENABLED' do
        around do |example|
          ClimateControl.modify('DD_PROFILING_ALLOCATION_ENABLED' => environment) do
            example.run
          end
        end

        context 'is not defined' do
          let(:environment) { nil }

          it { is_expected.to be false }
        end

        [true, false].each do |value|
          context "is defined as #{value}" do
            let(:environment) { value.to_s }

            it { is_expected.to be value }
          end
        end
      end
    end

    describe '#allocation_enabled=' do
      it 'updates the #allocation_enabled setting' do
        expect { settings.profiling.allocation_enabled = true }
          .to change { settings.profiling.allocation_enabled }
          .from(false)
          .to(true)
      end
    end

    describe '#advanced' do
      describe '#max_frames' do
        subject(:max_frames) { settings.profiling.advanced.max_frames }

        context "when #{Datadog::Profiling::Ext::ENV_MAX_FRAMES}" do
          around do |example|
            ClimateControl.modify(Datadog::Profiling::Ext::ENV_MAX_FRAMES => environment) do
              example.run
            end
          end

          context 'is not defined' do
            let(:environment) { nil }

            it { is_expected.to eq(400) }
          end

          context 'is defined' do
            let(:environment) { '123' }

            it { is_expected.to eq(123) }
          end
        end
      end

      describe '#max_frames=' do
        it 'updates the #max_frames setting' do
          expect { settings.profiling.advanced.max_frames = 456 }
            .to change { settings.profiling.advanced.max_frames }
            .from(400)
            .to(456)
        end
      end

      describe '#endpoint' do
        describe '#collection' do
          describe '#enabled' do
            subject(:enabled) { settings.profiling.advanced.endpoint.collection.enabled }

            context "when #{Datadog::Profiling::Ext::ENV_ENDPOINT_COLLECTION_ENABLED}" do
              around do |example|
                ClimateControl.modify(Datadog::Profiling::Ext::ENV_ENDPOINT_COLLECTION_ENABLED => environment) do
                  example.run
                end
              end

              context 'is not defined' do
                let(:environment) { nil }

                it { is_expected.to be true }
              end

              [true, false].each do |value|
                context "is defined as #{value}" do
                  let(:environment) { value.to_s }

                  it { is_expected.to be value }
                end
              end
            end
          end

          describe '#enabled=' do
            it 'updates the #enabled setting' do
              expect { settings.profiling.advanced.endpoint.collection.enabled = false }
                .to change { settings.profiling.advanced.endpoint.collection.enabled }
                .from(true)
                .to(false)
            end
          end
        end
      end

      describe '#code_provenance_enabled' do
        subject(:code_provenance_enabled) { settings.profiling.advanced.code_provenance_enabled }

        it { is_expected.to be true }
      end

      describe '#code_provenance_enabled=' do
        it 'updates the #code_provenance_enabled setting' do
          expect { settings.profiling.advanced.code_provenance_enabled = false }
            .to change { settings.profiling.advanced.code_provenance_enabled }
            .from(true)
            .to(false)
        end
      end

      describe '#gc_enabled' do
        subject(:gc_enabled) { settings.profiling.advanced.gc_enabled }

        context 'when DD_PROFILING_GC_ENABLED' do
          around do |example|
            ClimateControl.modify('DD_PROFILING_GC_ENABLED' => environment) do
              example.run
            end
          end

          context 'is not defined' do
            let(:environment) { nil }

            it { is_expected.to be true }
          end

          [true, false].each do |value|
            context "is defined as #{value}" do
              let(:environment) { value.to_s }

              it { is_expected.to be value }
            end
          end
        end
      end

      describe '#gc_enabled=' do
        it 'updates the #gc_enabled setting' do
          expect { settings.profiling.advanced.gc_enabled = false }
            .to change { settings.profiling.advanced.gc_enabled }
            .from(true)
            .to(false)
        end
      end

      describe '#experimental_heap_enabled' do
        subject(:experimental_heap_enabled) { settings.profiling.advanced.experimental_heap_enabled }

        context 'when DD_PROFILING_EXPERIMENTAL_HEAP_ENABLED' do
          around do |example|
            ClimateControl.modify('DD_PROFILING_EXPERIMENTAL_HEAP_ENABLED' => environment) do
              example.run
            end
          end

          context 'is not defined' do
            let(:environment) { nil }

            it { is_expected.to be false }
          end

          [true, false].each do |value|
            context "is defined as #{value}" do
              let(:environment) { value.to_s }

              it { is_expected.to be value }
            end
          end
        end
      end

      describe '#experimental_heap_enabled=' do
        it 'updates the #experimental_heap_enabled setting' do
          expect { settings.profiling.advanced.experimental_heap_enabled = true }
            .to change { settings.profiling.advanced.experimental_heap_enabled }
            .from(false)
            .to(true)
        end
      end

      describe '#experimental_heap_size_enabled' do
        subject(:experimental_heap_size_enabled) { settings.profiling.advanced.experimental_heap_size_enabled }

        context 'when DD_PROFILING_EXPERIMENTAL_HEAP_SIZE_ENABLED' do
          around do |example|
            ClimateControl.modify('DD_PROFILING_EXPERIMENTAL_HEAP_SIZE_ENABLED' => environment) do
              example.run
            end
          end

          context 'is not defined' do
            let(:environment) { nil }

            it { is_expected.to be true }
          end

          [true, false].each do |value|
            context "is defined as #{value}" do
              let(:environment) { value.to_s }

              it { is_expected.to be value }
            end
          end
        end
      end

      describe '#experimental_heap_size_enabled=' do
        it 'updates the #experimental_heap_size_enabled setting' do
          expect { settings.profiling.advanced.experimental_heap_size_enabled = false }
            .to change { settings.profiling.advanced.experimental_heap_size_enabled }
            .from(true)
            .to(false)
        end
      end

      describe '#experimental_heap_sample_rate' do
        subject(:experimental_heap_sample_rate) { settings.profiling.advanced.experimental_heap_sample_rate }

        context 'when DD_PROFILING_EXPERIMENTAL_HEAP_SAMPLE_RATE' do
          around do |example|
            ClimateControl.modify('DD_PROFILING_EXPERIMENTAL_HEAP_SAMPLE_RATE' => environment) do
              example.run
            end
          end

          context 'is not defined' do
            let(:environment) { nil }

            it { is_expected.to be 10 }
          end

          context 'is defined as 100' do
            let(:environment) { '100' }

            it { is_expected.to eq(100) }
          end
        end
      end

      describe '#experimental_heap_sample_rate=' do
        it 'updates the #experimental_heap_sample_rate setting' do
          expect { settings.profiling.advanced.experimental_heap_sample_rate = 100 }
            .to change { settings.profiling.advanced.experimental_heap_sample_rate }
            .from(10)
            .to(100)
        end
      end

      describe '#skip_mysql2_check' do
        subject(:skip_mysql2_check) { settings.profiling.advanced.skip_mysql2_check }

        context 'when DD_PROFILING_SKIP_MYSQL2_CHECK' do
          around do |example|
            ClimateControl.modify('DD_PROFILING_SKIP_MYSQL2_CHECK' => environment) do
              example.run
            end
          end

          context 'is not defined' do
            let(:environment) { nil }

            it { is_expected.to be false }
          end

          [true, false].each do |value|
            context "is defined as #{value}" do
              let(:environment) { value.to_s }

              it { is_expected.to be value }
            end
          end
        end
      end

      describe '#skip_mysql2_check=' do
        it 'updates the #skip_mysql2_check setting' do
          expect { settings.profiling.advanced.skip_mysql2_check = true }
            .to change { settings.profiling.advanced.skip_mysql2_check }
            .from(false)
            .to(true)
        end
      end

      describe '#no_signals_workaround_enabled' do
        subject(:no_signals_workaround_enabled) { settings.profiling.advanced.no_signals_workaround_enabled }

        context 'when DD_PROFILING_NO_SIGNALS_WORKAROUND_ENABLED' do
          around do |example|
            ClimateControl.modify('DD_PROFILING_NO_SIGNALS_WORKAROUND_ENABLED' => environment) do
              example.run
            end
          end

          context 'is not defined' do
            let(:environment) { nil }

            it { is_expected.to be :auto }
          end

          [true, false].each do |value|
            context "is defined as #{value}" do
              let(:environment) { value.to_s }

              it { is_expected.to be value }
            end
          end
        end
      end

      describe '#no_signals_workaround_enabled=' do
        it 'updates the #no_signals_workaround_enabled setting' do
          expect { settings.profiling.advanced.no_signals_workaround_enabled = false }
            .to change { settings.profiling.advanced.no_signals_workaround_enabled }
            .from(:auto)
            .to(false)
        end
      end

      describe '#timeline_enabled' do
        subject(:timeline_enabled) { settings.profiling.advanced.timeline_enabled }

        context 'when DD_PROFILING_TIMELINE_ENABLED' do
          around do |example|
            ClimateControl.modify('DD_PROFILING_TIMELINE_ENABLED' => environment) do
              example.run
            end
          end

          context 'is not defined' do
            let(:environment) { nil }

            it { is_expected.to be true }
          end

          [true, false].each do |value|
            context "is defined as #{value}" do
              let(:environment) { value.to_s }

              it { is_expected.to be value }
            end
          end
        end
      end

      describe '#timeline_enabled=' do
        it 'updates the #timeline_enabled setting from its default of true' do
          expect { settings.profiling.advanced.timeline_enabled = false }
            .to change { settings.profiling.advanced.timeline_enabled }
            .from(true)
            .to(false)
        end
      end

      describe '#overhead_target_percentage' do
        subject(:timeout_seconds) { settings.profiling.advanced.overhead_target_percentage }

        context 'when DD_PROFILING_OVERHEAD_TARGET_PERCENTAGE' do
          around do |example|
            ClimateControl.modify('DD_PROFILING_OVERHEAD_TARGET_PERCENTAGE' => environment) do
              example.run
            end
          end

          context 'is not defined' do
            let(:environment) { nil }

            it { is_expected.to eq(2.0) }
          end

          context 'is defined' do
            let(:environment) { '1.23' }

            it { is_expected.to eq(1.23) }
          end
        end
      end

      describe '#overhead_target_percentage=' do
        it 'updates the #overhead_target_percentage setting' do
          expect { settings.profiling.advanced.overhead_target_percentage = 4.56 }
            .to change { settings.profiling.advanced.overhead_target_percentage }
            .from(2.0)
            .to(4.56)
        end
      end

      describe '#upload_period_seconds' do
        subject(:max_frames) { settings.profiling.advanced.upload_period_seconds }

        context 'when DD_PROFILING_UPLOAD_PERIOD' do
          around do |example|
            ClimateControl.modify('DD_PROFILING_UPLOAD_PERIOD' => environment) do
              example.run
            end
          end

          context 'is not defined' do
            let(:environment) { nil }

            it { is_expected.to eq(60) }
          end

          context 'is defined' do
            let(:environment) { '123' }

            it { is_expected.to eq(123) }
          end
        end
      end

      describe '#upload_period_seconds=' do
        it 'updates the #upload_period_seconds setting' do
          expect { settings.profiling.advanced.upload_period_seconds = 90 }
            .to change { settings.profiling.advanced.upload_period_seconds }
            .from(60)
            .to(90)
        end
      end

      describe '#experimental_crash_tracking_enabled' do
        subject(:experimental_crash_tracking_enabled) { settings.profiling.advanced.experimental_crash_tracking_enabled }

        context 'when DD_PROFILING_EXPERIMENTAL_CRASH_TRACKING_ENABLED' do
          around do |example|
            ClimateControl.modify('DD_PROFILING_EXPERIMENTAL_CRASH_TRACKING_ENABLED' => environment) do
              example.run
            end
          end

          context 'is not defined' do
            let(:environment) { nil }

            it { is_expected.to be false }
          end

          [true, false].each do |value|
            context "is defined as #{value}" do
              let(:environment) { value.to_s }

              it { is_expected.to be value }
            end
          end
        end
      end

      describe '#experimental_crash_tracking_enabled=' do
        it 'updates the #experimental_crash_tracking_enabled setting' do
          expect { settings.profiling.advanced.experimental_crash_tracking_enabled = true }
            .to change { settings.profiling.advanced.experimental_crash_tracking_enabled }
            .from(false)
            .to(true)
        end
      end

      describe '#dir_interruption_workaround_enabled' do
        subject(:dir_interruption_workaround_enabled) { settings.profiling.advanced.dir_interruption_workaround_enabled }

        context 'when DD_PROFILING_DIR_INTERRUPTION_WORKAROUND_ENABLED' do
          around do |example|
            ClimateControl.modify('DD_PROFILING_DIR_INTERRUPTION_WORKAROUND_ENABLED' => environment) do
              example.run
            end
          end

          context 'is not defined' do
            let(:environment) { nil }

            it { is_expected.to be true }
          end

          [true, false].each do |value|
            context "is defined as #{value}" do
              let(:environment) { value.to_s }

              it { is_expected.to be value }
            end
          end
        end
      end

      describe '#dir_interruption_workaround_enabled=' do
        it 'updates the #dir_interruption_workaround_enabled setting from its default of true' do
          expect { settings.profiling.advanced.dir_interruption_workaround_enabled = false }
            .to change { settings.profiling.advanced.dir_interruption_workaround_enabled }
            .from(true)
            .to(false)
        end
      end
    end

    describe '#upload' do
      describe '#timeout_seconds' do
        subject(:timeout_seconds) { settings.profiling.upload.timeout_seconds }

        context "when #{Datadog::Profiling::Ext::ENV_UPLOAD_TIMEOUT}" do
          around do |example|
            ClimateControl.modify(Datadog::Profiling::Ext::ENV_UPLOAD_TIMEOUT => environment) do
              example.run
            end
          end

          context 'is not defined' do
            let(:environment) { nil }

            it { is_expected.to eq(30.0) }
          end

          context 'is defined' do
            let(:environment) { '10.0' }

            it { is_expected.to eq(10.0) }
          end
        end
      end

      describe '#timeout_seconds=' do
        it 'updates the #timeout_seconds setting' do
          expect { settings.profiling.upload.timeout_seconds = 10.0 }
            .to change { settings.profiling.upload.timeout_seconds }
            .from(30.0)
            .to(10.0)
        end
      end
    end
  end

  describe '#runtime_metrics' do
    describe '#enabled' do
      subject(:enabled) { settings.runtime_metrics.enabled }

      context "when #{Datadog::Core::Runtime::Ext::Metrics::ENV_ENABLED}" do
        around do |example|
          ClimateControl.modify(Datadog::Core::Runtime::Ext::Metrics::ENV_ENABLED => environment) do
            example.run
          end
        end

        context 'is not defined' do
          let(:environment) { nil }

          it { is_expected.to be false }
        end

        context 'is defined' do
          let(:environment) { 'true' }

          it { is_expected.to be true }
        end
      end
    end

    describe '#enabled=' do
      after { settings.runtime_metrics.reset! }

      it 'changes the #enabled setting' do
        expect { settings.runtime_metrics.enabled = true }
          .to change { settings.runtime_metrics.enabled }
          .from(false)
          .to(true)
      end
    end

    describe '#opts' do
      subject(:opts) { settings.runtime_metrics.opts }

      it { is_expected.to eq({}) }
    end

    describe '#opts=' do
      let(:opts) { { a: :b } }

      it 'changes the #opts setting' do
        expect { settings.runtime_metrics.opts = opts }
          .to change { settings.runtime_metrics.opts }
          .from({})
          .to(opts)
      end
    end

    describe '#statsd' do
      subject(:statsd) { settings.runtime_metrics.statsd }

      it { is_expected.to be nil }
    end

    describe '#statsd=' do
      let(:statsd) { double('statsd') }

      it 'changes the #statsd setting' do
        expect { settings.runtime_metrics.statsd = statsd }
          .to change { settings.runtime_metrics.statsd }
          .from(nil)
          .to(statsd)
      end
    end
  end

  describe '#service' do
    subject(:service) { settings.service }

    context "when #{Datadog::Core::Environment::Ext::ENV_SERVICE}" do
      around do |example|
        ClimateControl.modify(Datadog::Core::Environment::Ext::ENV_SERVICE => env_service) do
          example.run
        end
      end

      context 'is not defined' do
        let(:env_service) { nil }

        it { is_expected.to include 'rspec' }
      end

      context 'is defined' do
        let(:env_service) { 'service-value' }

        it { is_expected.to eq(service) }
      end
    end

    context 'when a service tag is defined in DD_TAGS' do
      around do |example|
        ClimateControl.modify(Datadog::Core::Environment::Ext::ENV_TAGS => 'service:service-name-from-tag') do
          example.run
        end
      end

      it 'uses the service name from DD_TAGS' do
        is_expected.to eq('service-name-from-tag')
      end

      context 'and defined via DD_SERVICE and OTEL_SERVICE_NAME' do
        around do |example|
          ClimateControl.modify(
            Datadog::Core::Environment::Ext::ENV_SERVICE => 'service-name-from-dd-service',
            Datadog::Core::Environment::Ext::ENV_OTEL_SERVICE => 'otel-service-name'
          ) do
            example.run
          end
        end

        it 'uses the service name from DD_SERVICE' do
          is_expected.to eq('service-name-from-dd-service')
        end
      end

      context 'and defined via OTEL_SERVICE_NAME' do
        around do |example|
          ClimateControl.modify(Datadog::Core::Environment::Ext::ENV_OTEL_SERVICE => 'otel-service-name') do
            example.run
          end
        end

        it 'uses the service name from OTEL_SERVICE_NAME' do
          is_expected.to eq('otel-service-name')
        end
      end
    end
  end

  describe '#service=' do
    subject(:set_service) { settings.service = service }

    context 'when given a value' do
      let(:service) { 'custom-service' }

      before { set_service }

      it { expect(settings.service).to eq(service) }
    end

    context 'when given `nil`' do
      let(:service) { nil }

      before { set_service }

      it { expect(settings.service).to be_nil }
    end
  end

  describe '#service_without_fallback' do
    subject(:service_without_fallback) { settings.service_without_fallback }

    context 'when no service name is configured' do
      around do |example|
        ClimateControl.modify(Datadog::Core::Environment::Ext::ENV_SERVICE => nil) do
          example.run
        end
      end

      it { is_expected.to be nil }
    end

    context 'when a service name is configured' do
      around do |example|
        ClimateControl.modify(Datadog::Core::Environment::Ext::ENV_SERVICE => 'test_service_name') do
          example.run
        end
      end

      it 'returns the service name' do
        is_expected.to eq 'test_service_name'
      end
    end
  end

  describe '#site' do
    subject(:site) { settings.site }

    context "when #{Datadog::Core::Environment::Ext::ENV_SITE}" do
      around do |example|
        ClimateControl.modify(Datadog::Core::Environment::Ext::ENV_SITE => site_env) do
          example.run
        end
      end

      context 'is not defined' do
        let(:site_env) { nil }

        it { is_expected.to be nil }
      end

      context 'is defined' do
        let(:site_env) { 'datadoghq.com' }

        it { is_expected.to eq(site_env) }
      end
    end
  end

  describe '#site=' do
    subject(:set_site) { settings.site = site }

    context 'when given a value' do
      let(:site) { 'datadoghq.com' }

      before { set_site }

      it { expect(settings.site).to eq(site) }
    end
  end

  describe '#tags' do
    subject(:tags) { settings.tags }

    context "when #{Datadog::Core::Environment::Ext::ENV_TAGS}" do
      around do |example|
        ClimateControl.modify(Datadog::Core::Environment::Ext::ENV_TAGS => env_tags) do
          example.run
        end
      end

      context 'is not defined' do
        let(:env_tags) { nil }

        it { is_expected.to eq({}) }
      end

      context 'is defined' do
        let(:env_tags) { 'a:1,b:2' }

        it { is_expected.to include('a' => '1', 'b' => '2') }

        context 'with an invalid tag' do
          ['', 'a', ':', ',', 'a:'].each do |invalid_tag|
            context "when tag is #{invalid_tag.inspect}" do
              let(:env_tags) { invalid_tag }

              it { is_expected.to eq({}) }
            end
          end
        end

        context 'with multiple colons' do
          let(:env_tags) { 'key:va:lue' }

          it 'allows for colons in value' do
            is_expected.to eq('key' => 'va:lue')
          end
        end

        context 'and when #env' do
          let(:options) { { **super(), env: env } }

          context 'is set' do
            let(:env) { 'env-value' }

            it { is_expected.to include('env' => env) }
          end

          context 'is not set' do
            let(:env) { nil }

            it { is_expected.to_not include('env') }
          end
        end

        context 'and when #version' do
          let(:options) { { **super(), version: version } }

          context 'is set' do
            let(:version) { 'version-value' }

            it { is_expected.to include('version' => version) }
          end

          context 'is not set' do
            let(:version) { nil }

            it { is_expected.to_not include('version') }
          end
        end
      end

      context 'conflicts with #env' do
        let(:options) { { **super(), env: env_value } }

        let(:env_tags) { "env:#{tag_env_value}" }
        let(:tag_env_value) { 'tag-env-value' }
        let(:env_value) { 'env-value' }

        it { is_expected.to include('env' => env_value) }
      end

      context 'conflicts with #version' do
        let(:options) { { **super(), version: version_value } }

        let(:env_tags) { "env:#{tag_version_value}" }
        let(:tag_version_value) { 'tag-version-value' }
        let(:version_value) { 'version-value' }

        it { is_expected.to include('version' => version_value) }
      end
    end

    context "when #{Datadog::Core::Environment::Ext::ENV_OTEL_RESOURCE_ATTRIBUTES}" do
      around do |example|
        ClimateControl.modify(
          Datadog::Core::Environment::Ext::ENV_OTEL_RESOURCE_ATTRIBUTES => otel_tags,
          Datadog::Core::Environment::Ext::ENV_TAGS => dd_tags
        ) do
          example.run
        end
      end

      context 'is defined and DD_TAGS is set' do
        let(:otel_tags) { 'deployment.environment=prod,service.name=bleh,service.version=1.0,mkey=val1' }
        let(:dd_tags) { 'service:moon-test,version:v42069,env:prod,token:gg' }
        it { is_expected.to include('service' => 'moon-test', 'version' => 'v42069', 'env' => 'prod', 'token' => 'gg') }
      end

      context 'is defined and DD_TAGS is not set' do
        let(:otel_tags) { 'deployment.environment=prod,service.name=bleh,service.version=1.0,mkey=val1' }
        let(:dd_tags) { nil }
        it { is_expected.to include('env' => 'prod', 'service' => 'bleh', 'version' => '1.0', 'mkey' => 'val1') }
      end

      context 'is not defined and DD_TAGS is not set' do
        let(:otel_tags) { nil }
        let(:dd_tags) { nil }
        it { is_expected.to eq({}) }
      end
    end
  end

  describe '#tags=' do
    subject(:set_tags) { settings.tags = tags }

    context 'when given a Hash' do
      context 'with Symbol keys' do
        let(:tags) { { :'custom-tag' => 'custom-value' } }

        before { set_tags }

        it { expect(settings.tags).to eq('custom-tag' => 'custom-value') }
      end

      context 'with String keys' do
        let(:tags) { { 'custom-tag' => 'custom-value' } }

        before { set_tags }

        it { expect(settings.tags).to eq(tags) }
      end
    end

    context 'called consecutively' do
      subject(:set_tags) do
        settings.tags = { foo: 'foo', bar: 'bar' }
        settings.tags = { 'foo' => 'oof', 'baz' => 'baz' }
      end

      before { set_tags }

      it { expect(settings.tags).to eq('foo' => 'oof', 'bar' => 'bar', 'baz' => 'baz') }
    end
  end

  describe '#time_now_provider=' do
    subject(:set_time_now_provider) { settings.time_now_provider = time_now_provider }

    after { settings.reset! }

    let(:time_now) { double('time') }
    let(:time_now_provider) do
      now = time_now # Capture for closure
      -> { now }
    end

    context 'when default' do
      before { allow(Time).to receive(:now).and_return(time_now) }

      it 'delegates to Time.now' do
        expect(settings.time_now_provider.call).to be(time_now)
        expect(Datadog::Core::Utils::Time.now).to be(time_now)
      end
    end

    context 'when given a value' do
      before { set_time_now_provider }

      it 'returns the provided time' do
        expect(settings.time_now_provider.call).to be(time_now)
        expect(Datadog::Core::Utils::Time.now).to be(time_now)
      end
    end

    context 'then reset' do
      let(:original_time_now) { double('original time') }

      before do
        set_time_now_provider
        allow(Time).to receive(:now).and_return(original_time_now)
      end

      it 'returns the provided time' do
        expect(settings.time_now_provider.call).to be(time_now)
        expect(Datadog::Core::Utils::Time.now).to be(time_now)

        settings.reset!

        expect(settings.time_now_provider.call).to be(original_time_now)
        expect(Datadog::Core::Utils::Time.now).to be(original_time_now)
      end
    end
  end

  # Important note: These settings are used as inputs of the AgentSettingsResolver and are used by all components
  # that consume its result (e.g. tracing, profiling, and telemetry, as of January 2023).
  describe '#agent' do
    describe '#host' do
      subject(:host) { settings.agent.host }

      it { is_expected.to be nil }
    end

    describe '#host=' do
      let(:host) { 'my-agent' }

      it 'updates the #host setting' do
        expect { settings.agent.host = host }
          .to change { settings.agent.host }
          .from(nil)
          .to(host)
      end
    end

    describe '#tracer' do
      describe '#port' do
        subject(:port) { settings.agent.port }

        it { is_expected.to be nil }
      end

      describe '#port=' do
        let(:port) { 1234 }

        it 'updates the #port setting' do
          expect { settings.agent.port = port }
            .to change { settings.agent.port }
            .from(nil)
            .to(port)
        end
      end
    end
  end

  describe '#version' do
    subject(:version) { settings.version }

    context "when #{Datadog::Core::Environment::Ext::ENV_VERSION}" do
      around do |example|
        ClimateControl.modify(Datadog::Core::Environment::Ext::ENV_VERSION => version) do
          example.run
        end
      end

      context 'is not defined' do
        let(:version) { nil }

        it { is_expected.to be nil }
      end

      context 'is defined' do
        let(:version) { 'version-value' }

        it { is_expected.to eq(version) }
      end
    end

    context 'when a version tag is defined in DD_TAGS' do
      around do |example|
        ClimateControl.modify(Datadog::Core::Environment::Ext::ENV_TAGS => 'version:version-from-tag') do
          example.run
        end
      end

      it 'uses the version from DD_TAGS' do
        is_expected.to eq('version-from-tag')
      end

      context 'and defined via DD_VERSION' do
        around do |example|
          ClimateControl.modify(Datadog::Core::Environment::Ext::ENV_VERSION => 'version-from-dd-version') do
            example.run
          end
        end

        it 'uses the version from DD_VERSION' do
          is_expected.to eq('version-from-dd-version')
        end
      end
    end
  end

  describe '#version=' do
    subject(:set_version) { settings.version = version }

    context 'when given a value' do
      let(:version) { '0.1.0.alpha' }

      before { set_version }

      it { expect(settings.version).to eq(version) }
    end
  end

  describe '#telemetry' do
    around do |example|
      ClimateControl.modify(env_var_name => env_var_value) do
        example.run
      end
    end

    describe '#enabled' do
      subject(:enabled) { settings.telemetry.enabled }
      let(:env_var_name) { 'DD_INSTRUMENTATION_TELEMETRY_ENABLED' }

      context 'when DD_INSTRUMENTATION_TELEMETRY_ENABLED' do
        context 'is not defined' do
          let(:env_var_value) { nil }

          context 'in a development environment' do
            it { is_expected.to be false }
          end

          context 'not in a development environment' do
            include_context 'non-development execution environment'

            it { is_expected.to be true }
          end
        end

        [true, false].each do |value|
          context "is defined as #{value}" do
            let(:env_var_value) { value.to_s }

            it { is_expected.to be value }
          end
        end
      end
    end

    describe '#enabled=' do
      let(:env_var_name) { 'DD_INSTRUMENTATION_TELEMETRY_ENABLED' }
      let(:env_var_value) { 'true' }

      it 'updates the #enabled setting' do
        expect { settings.telemetry.enabled = false }
          .to change { settings.telemetry.enabled }
          .from(true)
          .to(false)
      end
    end

    describe '#heartbeat_interval' do
      subject(:heartbeat_interval_seconds) { settings.telemetry.heartbeat_interval_seconds }
      let(:env_var_name) { 'DD_TELEMETRY_HEARTBEAT_INTERVAL' }

      context 'when DD_TELEMETRY_HEARTBEAT_INTERVAL' do
        context 'is not defined' do
          let(:env_var_value) { nil }

          it { is_expected.to eq 60.0 }
        end

        context 'is defined' do
          let(:env_var_value) { '1.1' }

          it { is_expected.to eq 1.1 }
        end
      end
    end

    describe '#heartbeat_interval=' do
      let(:env_var_name) { 'DD_TELEMETRY_HEARTBEAT_INTERVAL' }
      let(:env_var_value) { '1.1' }

      it 'updates the #heartbeat_interval setting' do
        expect { settings.telemetry.heartbeat_interval_seconds = 2.2 }
          .to change { settings.telemetry.heartbeat_interval_seconds }.from(1.1).to(2.2)
      end
    end

    describe '#install_id' do
      subject(:install_id) { settings.telemetry.install_id }
      let(:env_var_name) { 'DD_INSTRUMENTATION_INSTALL_ID' }

      context 'when DD_INSTRUMENTATION_INSTALL_ID' do
        context 'is not defined' do
          let(:env_var_value) { nil }

          it { is_expected.to eq nil }
        end

        context 'is defined' do
          let(:env_var_value) { '68e75c48-57ca-4a12-adfc-575c4b05fcbe' }

          it { is_expected.to eq '68e75c48-57ca-4a12-adfc-575c4b05fcbe' }
        end
      end
    end

    describe '#install_id=' do
      let(:env_var_name) { 'DD_INSTRUMENTATION_INSTALL_ID' }
      let(:env_var_value) { '68e75c48-57ca-4a12-adfc-575c4b05fcbe' }

      it 'updates the #install_id setting' do
        expect { settings.telemetry.install_id = 'abc123' }
          .to change { settings.telemetry.install_id }
          .from('68e75c48-57ca-4a12-adfc-575c4b05fcbe')
          .to('abc123')
      end
    end

    describe '#install_type' do
      subject(:install_id) { settings.telemetry.install_type }
      let(:env_var_name) { 'DD_INSTRUMENTATION_INSTALL_TYPE' }

      context 'when DD_INSTRUMENTATION_INSTALL_TYPE' do
        context 'is not defined' do
          let(:env_var_value) { nil }

          it { is_expected.to eq nil }
        end

        context 'is defined' do
          let(:env_var_value) { 'k8s_single_step' }

          it { is_expected.to eq 'k8s_single_step' }
        end
      end
    end

    describe '#install_type=' do
      let(:env_var_name) { 'DD_INSTRUMENTATION_INSTALL_TYPE' }
      let(:env_var_value) { 'k8s_single_step' }

      it 'updates the #install_type setting' do
        expect { settings.telemetry.install_type = 'abc123' }
          .to change { settings.telemetry.install_type }
          .from('k8s_single_step')
          .to('abc123')
      end
    end

    describe '#install_time' do
      subject(:install_id) { settings.telemetry.install_time }
      let(:env_var_name) { 'DD_INSTRUMENTATION_INSTALL_TIME' }

      context 'when DD_INSTRUMENTATION_INSTALL_TIME' do
        context 'is not defined' do
          let(:env_var_value) { nil }

          it { is_expected.to eq nil }
        end

        context 'is defined' do
          let(:env_var_value) { '1703188212' }

          it { is_expected.to eq '1703188212' }
        end
      end
    end

    describe '#install_time=' do
      let(:env_var_name) { 'DD_INSTRUMENTATION_INSTALL_TIME' }
      let(:env_var_value) { '1703188212' }

      it 'updates the #install_time setting' do
        expect { settings.telemetry.install_time = 'abc123' }
          .to change { settings.telemetry.install_time }
          .from('1703188212')
          .to('abc123')
      end
    end
  end

  describe '#remote' do
    describe '#enabled' do
      subject(:enabled) { settings.remote.enabled }

      context "when #{Datadog::Core::Remote::Ext::ENV_ENABLED}" do
        around do |example|
          ClimateControl.modify(Datadog::Core::Remote::Ext::ENV_ENABLED => environment) do
            example.run
          end
        end

        context 'is not defined' do
          let(:environment) { nil }

          context 'in a development environment' do
            it { is_expected.to be false }
          end

          context 'not in a development environment' do
            include_context 'non-development execution environment'

            it { is_expected.to be true }
          end
        end

        context 'is defined' do
          let(:environment) { 'true' }

          it { is_expected.to be true }
        end
      end
    end

    describe '#enabled=' do
      include_context 'non-development execution environment'

      it 'updates the #enabled setting' do
        expect { settings.remote.enabled = false }
          .to change { settings.remote.enabled }
          .from(true)
          .to(false)
      end
    end

    describe '#poll_interval_seconds' do
      subject(:enabled) { settings.remote.poll_interval_seconds }

      context "when #{Datadog::Core::Remote::Ext::ENV_POLL_INTERVAL_SECONDS}" do
        around do |example|
          ClimateControl.modify(Datadog::Core::Remote::Ext::ENV_POLL_INTERVAL_SECONDS => environment) do
            example.run
          end
        end

        context 'is not defined' do
          let(:environment) { nil }

          it { is_expected.to eq 5.0 }
        end

        context 'is defined' do
          let(:environment) { '1' }

          it { is_expected.to eq 1.0 }
        end
      end
    end

    describe '#poll_interval_seconds=' do
      it 'updates the #poll_interval_seconds setting' do
        expect { settings.remote.poll_interval_seconds = 1.0 }
          .to change { settings.remote.poll_interval_seconds }
          .from(5.0)
          .to(1.0)
      end
    end

    describe '#boot_timeout_seconds' do
      subject(:enabled) { settings.remote.boot_timeout_seconds }

      context "when #{Datadog::Core::Remote::Ext::ENV_BOOT_TIMEOUT_SECONDS}" do
        around do |example|
          ClimateControl.modify(Datadog::Core::Remote::Ext::ENV_BOOT_TIMEOUT_SECONDS => environment) do
            example.run
          end
        end

        context 'is not defined' do
          let(:environment) { nil }

          it { is_expected.to eq 1.0 }
        end

        context 'is defined' do
          let(:environment) { '2' }

          it { is_expected.to eq 2.0 }
        end
      end
    end

    describe '#boot_timeout_seconds=' do
      it 'updates the #boot_timeout_seconds setting' do
        expect { settings.remote.boot_timeout_seconds = 2.0 }
          .to change { settings.remote.boot_timeout_seconds }
          .from(1.0)
          .to(2.0)
      end
    end

    describe '#service' do
      subject(:service) { settings.remote.service }

      context 'defaults to nil' do
        it { is_expected.to be nil }
      end
    end

    describe '#service=' do
      it 'updates the #service setting' do
        expect { settings.remote.service = 'foo' }
          .to change { settings.remote.service }
          .from(nil)
          .to('foo')
      end
    end
  end
end
