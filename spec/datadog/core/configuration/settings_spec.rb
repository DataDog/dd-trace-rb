# typed: false

require 'spec_helper'

require 'securerandom'
require 'logger'

require 'datadog/core/configuration/settings'
require 'datadog/core/diagnostics/ext'
require 'datadog/core/environment/ext'
require 'datadog/core/runtime/ext'
require 'datadog/core/utils/time'
require 'datadog/profiling/ext'
require 'datadog/tracing/configuration/ext'
require 'datadog/tracing/flush'
require 'datadog/tracing/sampling/priority_sampler'
require 'datadog/tracing/tracer'
require 'datadog/tracing/writer'

RSpec.describe Datadog::Core::Configuration::Settings do
  subject(:settings) { described_class.new(options) }

  let(:options) { {} }

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

      context "when #{Datadog::Core::Diagnostics::Ext::DD_TRACE_DEBUG}" do
        around do |example|
          ClimateControl.modify(Datadog::Core::Diagnostics::Ext::DD_TRACE_DEBUG => environment) do
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

    describe '#health_metrics' do
      describe '#enabled' do
        subject(:enabled) { settings.diagnostics.health_metrics.enabled }

        context "when #{Datadog::Core::Diagnostics::Ext::Health::Metrics::ENV_ENABLED}" do
          around do |example|
            ClimateControl.modify(Datadog::Core::Diagnostics::Ext::Health::Metrics::ENV_ENABLED => environment) do
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
          expect { settings.diagnostics.health_metrics.enabled = true }
            .to change { settings.diagnostics.health_metrics.enabled }
            .from(false)
            .to(true)
        end
      end

      describe '#statsd' do
        subject(:statsd) { settings.diagnostics.health_metrics.statsd }

        it { is_expected.to be nil }
      end

      describe '#statsd=' do
        let(:statsd) { double('statsd') }

        it 'changes the #statsd setting' do
          expect { settings.diagnostics.health_metrics.statsd = statsd }
            .to change { settings.diagnostics.health_metrics.statsd }
            .from(nil)
            .to(statsd)
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
  end

  describe '#logger' do
    describe '#instance' do
      subject(:instance) { settings.logger.instance }

      it { is_expected.to be nil }
    end

    describe '#instance=' do
      let(:logger) do
        double(:logger,
               debug: true,
               info: true,
               warn: true,
               error: true,
               level: true)
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

    describe '#advanced' do
      describe '#max_events' do
        subject(:max_events) { settings.profiling.advanced.max_events }

        it { is_expected.to eq(32768) }
      end

      describe '#max_events=' do
        it 'updates the #max_events setting' do
          expect { settings.profiling.advanced.max_events = 1234 }
            .to change { settings.profiling.advanced.max_events }
            .from(32768)
            .to(1234)
        end
      end

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

              { 'true' => true, 'false' => false }.each do |string, value|
                context "is defined as #{string}" do
                  let(:environment) { string }

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
          expect { settings.profiling.upload.timeout_seconds = 10 }
            .to change { settings.profiling.upload.timeout_seconds }
            .from(30.0)
            .to(10.0)
        end

        context 'given nil' do
          it 'uses the default setting' do
            expect { settings.profiling.upload.timeout_seconds = nil }
              .to_not change { settings.profiling.upload.timeout_seconds }
              .from(30.0)
          end
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
      let(:opts) { double('opts') }

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

      context 'and defined via DD_SERVICE' do
        around do |example|
          ClimateControl.modify(Datadog::Core::Environment::Ext::ENV_SERVICE => 'service-name-from-dd-service') do
            example.run
          end
        end

        it 'uses the service name from DD_SERVICE' do
          is_expected.to eq('service-name-from-dd-service')
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

  describe '#tracing' do
    describe '#analytics' do
      describe '#enabled' do
        subject(:enabled) { settings.tracing.analytics.enabled }

        context "when #{Datadog::Tracing::Configuration::Ext::Analytics::ENV_TRACE_ANALYTICS_ENABLED}" do
          around do |example|
            ClimateControl.modify(
              Datadog::Tracing::Configuration::Ext::Analytics::ENV_TRACE_ANALYTICS_ENABLED => environment
            ) do
              example.run
            end
          end

          context 'is not defined' do
            let(:environment) { nil }

            it { is_expected.to be nil }
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
          expect { settings.tracing.analytics.enabled = true }
            .to change { settings.tracing.analytics.enabled }
            .from(nil)
            .to(true)
        end
      end
    end

    describe '#distributed_tracing' do
      describe '#propagation_extract_style' do
        subject(:propagation_extract_style) { settings.tracing.distributed_tracing.propagation_extract_style }

        context "when #{Datadog::Tracing::Configuration::Ext::Distributed::ENV_PROPAGATION_STYLE_EXTRACT}" do
          around do |example|
            ClimateControl.modify(
              Datadog::Tracing::Configuration::Ext::Distributed::ENV_PROPAGATION_STYLE_EXTRACT => environment
            ) do
              example.run
            end
          end

          context 'is not defined' do
            let(:environment) { nil }

            it do
              is_expected.to eq(
                [
                  Datadog::Tracing::Configuration::Ext::Distributed::PROPAGATION_STYLE_DATADOG,
                  Datadog::Tracing::Configuration::Ext::Distributed::PROPAGATION_STYLE_B3,
                  Datadog::Tracing::Configuration::Ext::Distributed::PROPAGATION_STYLE_B3_SINGLE_HEADER
                ]
              )
            end
          end

          context 'is defined' do
            let(:environment) { 'B3,B3 single header' }

            it do
              is_expected.to eq(
                [
                  Datadog::Tracing::Configuration::Ext::Distributed::PROPAGATION_STYLE_B3,
                  Datadog::Tracing::Configuration::Ext::Distributed::PROPAGATION_STYLE_B3_SINGLE_HEADER
                ]
              )
            end
          end
        end
      end

      describe '#propagation_inject_style' do
        subject(:propagation_inject_style) { settings.tracing.distributed_tracing.propagation_inject_style }

        context "when #{Datadog::Tracing::Configuration::Ext::Distributed::ENV_PROPAGATION_STYLE_INJECT}" do
          around do |example|
            ClimateControl.modify(
              Datadog::Tracing::Configuration::Ext::Distributed::ENV_PROPAGATION_STYLE_INJECT => environment
            ) do
              example.run
            end
          end

          context 'is not defined' do
            let(:environment) { nil }

            it { is_expected.to eq([Datadog::Tracing::Configuration::Ext::Distributed::PROPAGATION_STYLE_DATADOG]) }
          end

          context 'is defined' do
            let(:environment) { 'Datadog,B3' }

            it do
              is_expected.to eq(
                [
                  Datadog::Tracing::Configuration::Ext::Distributed::PROPAGATION_STYLE_DATADOG,
                  Datadog::Tracing::Configuration::Ext::Distributed::PROPAGATION_STYLE_B3
                ]
              )
            end
          end
        end
      end
    end

    describe '#enabled' do
      subject(:enabled) { settings.tracing.enabled }

      it { is_expected.to be true }

      context "when #{Datadog::Core::Diagnostics::Ext::DD_TRACE_ENABLED}" do
        around do |example|
          ClimateControl.modify(Datadog::Core::Diagnostics::Ext::DD_TRACE_ENABLED => enable) do
            example.run
          end
        end

        context 'is not defined' do
          let(:enable) { nil }

          it { is_expected.to be true }
        end

        context 'is set to true' do
          let(:enable) { 'true' }

          it { is_expected.to be true }
        end

        context 'is set to false' do
          let(:enable) { 'false' }

          it { is_expected.to be false }
        end
      end
    end

    describe '#enabled=' do
      it 'updates the #enabled setting' do
        expect { settings.tracing.enabled = false }
          .to change { settings.tracing.enabled }
          .from(true)
          .to(false)
      end
    end

    describe '#instance' do
      subject(:instance) { settings.tracing.instance }

      it { is_expected.to be nil }
    end

    describe '#instance=' do
      let(:tracer) { instance_double(Datadog::Tracing::Tracer) }

      it 'updates the #instance setting' do
        expect { settings.tracing.instance = tracer }
          .to change { settings.tracing.instance }
          .from(nil)
          .to(tracer)
      end
    end

    describe '#log_injection' do
      subject(:log_injection) { settings.tracing.log_injection }

      context "when #{Datadog::Tracing::Configuration::Ext::Correlation::ENV_LOGS_INJECTION_ENABLED}" do
        around do |example|
          ClimateControl.modify(
            Datadog::Tracing::Configuration::Ext::Correlation::ENV_LOGS_INJECTION_ENABLED => log_injection_env
          ) do
            example.run
          end
        end

        context 'is not defined' do
          let(:log_injection_env) { nil }

          it { is_expected.to be(true) }
        end

        context 'is defined' do
          let(:log_injection_env) { 'false' }

          it { is_expected.to be(false) }
        end
      end
    end

    describe '#partial_flush' do
      describe '#enabled' do
        subject(:enabled) { settings.tracing.partial_flush.enabled }

        it { is_expected.to be false }
      end

      describe '#enabled=' do
        it 'updates the #enabled setting' do
          expect { settings.tracing.partial_flush.enabled = true }
            .to change { settings.tracing.partial_flush.enabled }
            .from(false)
            .to(true)
        end
      end

      describe '#min_spans_threshold' do
        subject(:min_spans_threshold) { settings.tracing.partial_flush.min_spans_threshold }

        it { is_expected.to eq(500) }
      end

      describe '#min_spans_threshold=' do
        let(:value) { 1234 }

        it 'updates the #min_spans_before_partial_flush setting' do
          expect { settings.tracing.partial_flush.min_spans_threshold = value }
            .to change { settings.tracing.partial_flush.min_spans_threshold }
            .from(500)
            .to(value)
        end
      end
    end

    describe '#priority_sampling' do
      subject(:priority_sampling) { settings.tracing.priority_sampling }

      it { is_expected.to be nil }
    end

    describe '#priority_sampling=' do
      it 'updates the #priority_sampling setting' do
        expect { settings.tracing.priority_sampling = true }
          .to change { settings.tracing.priority_sampling }
          .from(nil)
          .to(true)
      end
    end

    describe '#report_hostname' do
      subject(:report_hostname) { settings.tracing.report_hostname }

      context "when #{Datadog::Tracing::Configuration::Ext::NET::ENV_REPORT_HOSTNAME}" do
        around do |example|
          ClimateControl.modify(Datadog::Tracing::Configuration::Ext::NET::ENV_REPORT_HOSTNAME => environment) do
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

    describe '#report_hostname=' do
      it 'changes the #report_hostname setting' do
        expect { settings.tracing.report_hostname = true }
          .to change { settings.tracing.report_hostname }
          .from(false)
          .to(true)
      end
    end

    describe '#sampler' do
      subject(:sampler) { settings.tracing.sampler }

      it { is_expected.to be nil }
    end

    describe '#sampler=' do
      let(:sampler) { instance_double(Datadog::Tracing::Sampling::PrioritySampler) }

      it 'updates the #sampler setting' do
        expect { settings.tracing.sampler = sampler }
          .to change { settings.tracing.sampler }
          .from(nil)
          .to(sampler)
      end
    end

    describe '#sampling' do
      describe '#rate_limit' do
        subject(:rate_limit) { settings.tracing.sampling.rate_limit }

        context 'default' do
          it { is_expected.to eq(100) }
        end

        context 'when ENV is provided' do
          around do |example|
            ClimateControl.modify(Datadog::Tracing::Configuration::Ext::Sampling::ENV_RATE_LIMIT => '20.0') do
              example.run
            end
          end

          it { is_expected.to eq(20.0) }
        end
      end

      describe '#default_rate' do
        subject(:default_rate) { settings.tracing.sampling.default_rate }

        context 'default' do
          it { is_expected.to be nil }
        end

        context 'when ENV is provided' do
          around do |example|
            ClimateControl.modify(Datadog::Tracing::Configuration::Ext::Sampling::ENV_SAMPLE_RATE => '0.5') do
              example.run
            end
          end

          it { is_expected.to eq(0.5) }
        end
      end

      describe '#span_rules' do
        subject(:rules) { settings.tracing.sampling.span_rules }

        context 'default' do
          it { is_expected.to be nil }
        end

        context 'when DD_SPAN_SAMPLING_RULES is provided' do
          around do |example|
            ClimateControl.modify(
              Datadog::Tracing::Configuration::Ext::Sampling::Span::ENV_SPAN_SAMPLING_RULES => '{}'
            ) do
              example.run
            end
          end

          it { is_expected.to eq('{}') }

          context 'and DD_SPAN_SAMPLING_RULES_FILE is also provided' do
            around do |example|
              ClimateControl.modify(
                Datadog::Tracing::Configuration::Ext::Sampling::Span::ENV_SPAN_SAMPLING_RULES_FILE => 'path'
              ) do
                example.run
              end
            end

            it 'emits a conflict warning and returns DD_SPAN_SAMPLING_RULES' do
              expect(Datadog.logger).to receive(:warn).with(include('configuration conflict'))
              is_expected.to eq('{}')
            end
          end
        end

        context 'when DD_SPAN_SAMPLING_RULES_FILE is provided' do
          around do |example|
            Tempfile.open('DD_SPAN_SAMPLING_RULES_FILE') do |f|
              f.write('{from:"file"}')
              f.flush

              ClimateControl.modify(
                Datadog::Tracing::Configuration::Ext::Sampling::Span::ENV_SPAN_SAMPLING_RULES_FILE => f.path
              ) do
                example.run
              end
            end
          end

          it { is_expected.to eq('{from:"file"}') }
        end
      end
    end

    describe '#test_mode' do
      describe '#enabled' do
        subject(:enabled) { settings.tracing.test_mode.enabled }

        it { is_expected.to be false }

        context "when #{Datadog::Tracing::Configuration::Ext::Test::ENV_MODE_ENABLED}" do
          around do |example|
            ClimateControl.modify(Datadog::Tracing::Configuration::Ext::Test::ENV_MODE_ENABLED => enable) do
              example.run
            end
          end

          context 'is not defined' do
            let(:enable) { nil }

            it { is_expected.to be false }
          end

          context 'is set to true' do
            let(:enable) { 'true' }

            it { is_expected.to be true }
          end

          context 'is set to false' do
            let(:enable) { 'false' }

            it { is_expected.to be false }
          end
        end
      end

      describe '#trace_flush' do
        subject(:trace_flush) { settings.tracing.test_mode.trace_flush }

        context 'default' do
          it { is_expected.to be nil }
        end
      end

      describe '#trace_flush=' do
        let(:trace_flush) { instance_double(Datadog::Tracing::Flush::Finished) }

        it 'updates the #trace_flush setting' do
          expect { settings.tracing.test_mode.trace_flush = trace_flush }
            .to change { settings.tracing.test_mode.trace_flush }
            .from(nil)
            .to(trace_flush)
        end
      end

      describe '#enabled=' do
        it 'updates the #enabled setting' do
          expect { settings.tracing.test_mode.enabled = true }
            .to change { settings.tracing.test_mode.enabled }
            .from(false)
            .to(true)
        end
      end

      describe '#writer_options' do
        subject(:writer_options) { settings.tracing.test_mode.writer_options }

        it { is_expected.to eq({}) }

        context 'when modified' do
          it 'does not modify the default by reference' do
            settings.tracing.test_mode.writer_options[:foo] = :bar
            expect(settings.tracing.test_mode.writer_options).to_not be_empty
            expect(settings.tracing.test_mode.options[:writer_options].default_value).to be_empty
          end
        end
      end

      describe '#writer_options=' do
        let(:options) { { priority_sampling: true } }

        it 'updates the #writer_options setting' do
          expect { settings.tracing.test_mode.writer_options = options }
            .to change { settings.tracing.test_mode.writer_options }
            .from({})
            .to(options)
        end
      end
    end

    describe '#transport_options' do
      subject(:transport_options) { settings.tracing.transport_options }

      it { is_expected.to be nil }
    end

    describe '#transport_options=' do
      let(:config_proc) { proc { |t| t.adapter :test } }

      it 'updates the #transport_options setting' do
        expect { settings.tracing.transport_options = config_proc }
          .to change { settings.tracing.transport_options }
          .from(nil)
          .to(config_proc)
      end
    end

    describe '#writer' do
      subject(:writer) { settings.tracing.writer }

      it { is_expected.to be nil }
    end

    describe '#writer=' do
      let(:writer) { instance_double(Datadog::Tracing::Writer) }

      it 'updates the #writer setting' do
        expect { settings.tracing.writer = writer }
          .to change { settings.tracing.writer }
          .from(nil)
          .to(writer)
      end
    end

    describe '#writer_options' do
      subject(:writer_options) { settings.tracing.writer_options }

      it { is_expected.to eq({}) }

      context 'when modified' do
        it 'does not modify the default by reference' do
          settings.tracing.writer_options[:foo] = :bar
          expect(settings.tracing.writer_options).to_not be_empty
          expect(settings.tracing.options[:writer_options].default_value).to be_empty
        end
      end
    end

    describe '#writer_options=' do
      let(:options) { { priority_sampling: true } }

      it 'updates the #writer_options setting' do
        expect { settings.tracing.writer_options = options }
          .to change { settings.tracing.writer_options }
          .from({})
          .to(options)
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
end
