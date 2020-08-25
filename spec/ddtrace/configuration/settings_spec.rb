require 'spec_helper'
require 'securerandom'

require 'ddtrace'
require 'ddtrace/configuration/settings'

RSpec.describe Datadog::Configuration::Settings do
  subject(:settings) { described_class.new }

  describe '#analytics' do
    describe '#enabled' do
      subject(:enabled) { settings.analytics.enabled }

      context "when #{Datadog::Ext::Analytics::ENV_TRACE_ANALYTICS_ENABLED}" do
        around do |example|
          ClimateControl.modify(Datadog::Ext::Analytics::ENV_TRACE_ANALYTICS_ENABLED => environment) do
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
      it 'changes the #enabled setting' do
        expect { settings.analytics.enabled = true }
          .to change { settings.analytics.enabled }
          .from(nil)
          .to(true)
      end
    end
  end

  describe '#analytics_enabled' do
    subject(:analytics_enabled) { settings.analytics_enabled }
    let(:value) { double }

    before { expect(settings.analytics).to receive(:enabled).and_return(value) }

    it 'retrieves the value from the new setting' do
      is_expected.to be value
    end
  end

  describe '#analytics_enabled=' do
    it 'changes the new #enabled setting' do
      expect { settings.analytics_enabled = true }
        .to change { settings.analytics.enabled }
        .from(nil)
        .to(true)
    end
  end

  describe '#api_key' do
    subject(:api_key) { settings.api_key }

    context "when #{Datadog::Ext::Environment::ENV_API_KEY}" do
      around do |example|
        ClimateControl.modify(Datadog::Ext::Environment::ENV_API_KEY => api_key_env) do
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

      context "when #{Datadog::Ext::Diagnostics::DD_TRACE_DEBUG}" do
        around do |example|
          ClimateControl.modify(Datadog::Ext::Diagnostics::DD_TRACE_DEBUG => environment) do
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
      it 'updates the #debug setting' do
        expect { settings.diagnostics.debug = true }
          .to change { settings.diagnostics.debug }
          .from(false)
          .to(true)
      end
    end

    describe '#health_metrics' do
      describe '#enabled' do
        subject(:enabled) { settings.diagnostics.health_metrics.enabled }

        context "when #{Datadog::Ext::Diagnostics::Health::Metrics::ENV_ENABLED}" do
          around do |example|
            ClimateControl.modify(Datadog::Ext::Diagnostics::Health::Metrics::ENV_ENABLED => environment) do
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

  describe '#distributed_tracing' do
    describe '#propagation_extract_style' do
      subject(:propagation_extract_style) { settings.distributed_tracing.propagation_extract_style }

      context "when #{Datadog::Ext::DistributedTracing::PROPAGATION_EXTRACT_STYLE_ENV}" do
        around do |example|
          ClimateControl.modify(Datadog::Ext::DistributedTracing::PROPAGATION_EXTRACT_STYLE_ENV => environment) do
            example.run
          end
        end

        context 'is not defined' do
          let(:environment) { nil }
          it do
            is_expected.to eq(
              [
                Datadog::Ext::DistributedTracing::PROPAGATION_STYLE_DATADOG,
                Datadog::Ext::DistributedTracing::PROPAGATION_STYLE_B3,
                Datadog::Ext::DistributedTracing::PROPAGATION_STYLE_B3_SINGLE_HEADER
              ]
            )
          end
        end

        context 'is defined' do
          let(:environment) { 'B3,B3 single header' }
          it do
            is_expected.to eq(
              [
                Datadog::Ext::DistributedTracing::PROPAGATION_STYLE_B3,
                Datadog::Ext::DistributedTracing::PROPAGATION_STYLE_B3_SINGLE_HEADER
              ]
            )
          end
        end
      end
    end

    describe '#propagation_inject_style' do
      subject(:propagation_inject_style) { settings.distributed_tracing.propagation_inject_style }

      context "when #{Datadog::Ext::DistributedTracing::PROPAGATION_INJECT_STYLE_ENV}" do
        around do |example|
          ClimateControl.modify(Datadog::Ext::DistributedTracing::PROPAGATION_INJECT_STYLE_ENV => environment) do
            example.run
          end
        end

        context 'is not defined' do
          let(:environment) { nil }
          it { is_expected.to eq([Datadog::Ext::DistributedTracing::PROPAGATION_STYLE_DATADOG]) }
        end

        context 'is defined' do
          let(:environment) { 'Datadog,B3' }
          it do
            is_expected.to eq(
              [
                Datadog::Ext::DistributedTracing::PROPAGATION_STYLE_DATADOG,
                Datadog::Ext::DistributedTracing::PROPAGATION_STYLE_B3
              ]
            )
          end
        end
      end
    end
  end

  describe '#env' do
    subject(:env) { settings.env }
    context "when #{Datadog::Ext::Environment::ENV_ENVIRONMENT}" do
      around do |example|
        ClimateControl.modify(Datadog::Ext::Environment::ENV_ENVIRONMENT => environment) do
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
      let(:logger) { Datadog::Logger.new(STDOUT) }

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

  describe '#logger=' do
    let(:logger) { Datadog::Logger.new(STDOUT) }

    it 'sets the logger instance' do
      expect { settings.logger = logger }.to change { settings.logger.instance }
        .from(nil)
        .to(logger)
    end
  end

  describe '#profiling' do
    describe '#cpu' do
      describe '#enabled' do
        subject(:enabled) { settings.profiling.cpu.enabled }
        it { is_expected.to be true }
      end

      describe '#enabled=' do
        it 'updates the #enabled setting' do
          expect { settings.profiling.cpu.enabled = false }
            .to change { settings.profiling.cpu.enabled }
            .from(true)
            .to(false)
        end
      end
    end

    describe '#enabled' do
      subject(:enabled) { settings.profiling.enabled }

      context "when #{Datadog::Ext::Profiling::ENV_ENABLED}" do
        around do |example|
          ClimateControl.modify(Datadog::Ext::Profiling::ENV_ENABLED => environment) do
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
      describe '#instances' do
        subject(:instances) { settings.profiling.exporter.instances }
        it { is_expected.to be nil }
      end

      describe '#instances=' do
        let(:instances) { [double('exporter')] }

        it 'updates the #instances setting' do
          expect { settings.profiling.exporter.instances = instances }
            .to change { settings.profiling.exporter.instances }
            .from(nil)
            .to(instances)
        end
      end

      describe '#timeout' do
        subject(:timeout) { settings.profiling.exporter.timeout }

        context "when #{Datadog::Ext::Profiling::ENV_UPLOAD_TIMEOUT}" do
          around do |example|
            ClimateControl.modify(Datadog::Ext::Profiling::ENV_UPLOAD_TIMEOUT => environment) do
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

      describe '#timeout=' do
        it 'updates the #timeout setting' do
          expect { settings.profiling.exporter.timeout = 10 }
            .to change { settings.profiling.exporter.timeout }
            .from(30.0)
            .to(10.0)
        end

        context 'given nil' do
          it 'uses the default setting' do
            expect { settings.profiling.exporter.timeout = nil }
              .to_not change { settings.profiling.exporter.timeout }
              .from(30.0)
          end
        end
      end

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

      describe '#transport_options' do
        subject(:transport_options) { settings.profiling.exporter.transport_options }
        it { is_expected.to eq({}) }
      end

      describe '#transport_options=' do
        let(:transport_options) { { timeout: 10 } }

        it 'updates the #transport_options setting' do
          expect { settings.profiling.exporter.transport_options = transport_options }
            .to change { settings.profiling.exporter.transport_options }
            .from({})
            .to(transport_options)
        end
      end
    end

    describe '#max_events' do
      subject(:max_events) { settings.profiling.max_events }
      it { is_expected.to eq(32768) }
    end

    describe '#max_events=' do
      it 'updates the #max_events setting' do
        expect { settings.profiling.max_events = 1234 }
          .to change { settings.profiling.max_events }
          .from(32768)
          .to(1234)
      end
    end
  end

  describe '#report_hostname' do
    subject(:report_hostname) { settings.report_hostname }

    context "when #{Datadog::Ext::NET::ENV_REPORT_HOSTNAME}" do
      around do |example|
        ClimateControl.modify(Datadog::Ext::NET::ENV_REPORT_HOSTNAME => environment) do
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
      expect { settings.report_hostname = true }
        .to change { settings.report_hostname }
        .from(false)
        .to(true)
    end
  end

  describe '#runtime_metrics' do
    describe 'old style' do
      context 'given nothing' do
        subject(:runtime_metrics) { settings.runtime_metrics }
        it 'returns the new settings object' do
          is_expected.to be_a_kind_of(Datadog::Configuration::Base)
        end
      end

      context 'given :enabled' do
        subject(:runtime_metrics) { settings.runtime_metrics enabled: true }

        it 'updates the new #enabled setting' do
          expect { settings.runtime_metrics enabled: true }
            .to change { settings.runtime_metrics.enabled }
            .from(false)
            .to(true)
        end
      end

      context 'given :statsd' do
        subject(:runtime_metrics) { settings.runtime_metrics statsd: statsd }
        let(:statsd) { double('statsd') }

        it 'updates the new #statsd setting' do
          expect { settings.runtime_metrics statsd: statsd }
            .to change { settings.runtime_metrics.statsd }
            .from(nil)
            .to(statsd)
        end
      end
    end

    describe '#enabled' do
      subject(:enabled) { settings.runtime_metrics.enabled }

      context "when #{Datadog::Ext::Runtime::Metrics::ENV_ENABLED}" do
        around do |example|
          ClimateControl.modify(Datadog::Ext::Runtime::Metrics::ENV_ENABLED => environment) do
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

  describe '#runtime_metrics_enabled' do
    subject(:runtime_metrics_enabled) { settings.runtime_metrics_enabled }
    let(:value) { double }

    before { expect(settings.runtime_metrics).to receive(:enabled).and_return(value) }

    it 'retrieves the value from the new setting' do
      is_expected.to be value
    end
  end

  describe '#runtime_metrics_enabled=' do
    it 'changes the new #enabled setting' do
      expect { settings.runtime_metrics_enabled = true }
        .to change { settings.runtime_metrics.enabled }
        .from(false)
        .to(true)
    end
  end

  describe '#sampling' do
    describe '#rate_limit' do
      subject(:rate_limit) { settings.sampling.rate_limit }

      context 'default' do
        it { is_expected.to eq(100) }
      end

      context 'when ENV is provided' do
        around do |example|
          ClimateControl.modify(Datadog::Ext::Sampling::ENV_RATE_LIMIT => '20.0') do
            example.run
          end
        end

        it { is_expected.to eq(20.0) }
      end
    end

    describe '#default_rate' do
      subject(:default_rate) { settings.sampling.default_rate }

      context 'default' do
        it { is_expected.to be nil }
      end

      context 'when ENV is provided' do
        around do |example|
          ClimateControl.modify(Datadog::Ext::Sampling::ENV_SAMPLE_RATE => '0.5') do
            example.run
          end
        end

        it { is_expected.to eq(0.5) }
      end
    end
  end

  describe '#service' do
    subject(:service) { settings.service }
    context "when #{Datadog::Ext::Environment::ENV_SERVICE}" do
      around do |example|
        ClimateControl.modify(Datadog::Ext::Environment::ENV_SERVICE => service) do
          example.run
        end
      end

      context 'is not defined' do
        let(:service) { nil }
        it { is_expected.to be nil }
      end

      context 'is defined' do
        let(:service) { 'service-value' }
        it { is_expected.to eq(service) }
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

  describe '#site' do
    subject(:site) { settings.site }

    context "when #{Datadog::Ext::Environment::ENV_SITE}" do
      around do |example|
        ClimateControl.modify(Datadog::Ext::Environment::ENV_SITE => site_env) do
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

    context "when #{Datadog::Ext::Environment::ENV_TAGS}" do
      around do |example|
        ClimateControl.modify(Datadog::Ext::Environment::ENV_TAGS => env_tags) do
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
          context do
            let(:env_tags) { '' }
            it { is_expected.to eq({}) }
          end

          context do
            let(:env_tags) { 'a' }
            it { is_expected.to eq({}) }
          end

          context do
            let(:env_tags) { ':' }
            it { is_expected.to eq({}) }
          end

          context do
            let(:env_tags) { ',' }
            it { is_expected.to eq({}) }
          end

          context do
            let(:env_tags) { 'a:' }
            it { is_expected.to eq({}) }
          end
        end

        context 'and when #env' do
          before { allow(settings).to receive(:env).and_return(env) }

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
          before { allow(settings).to receive(:version).and_return(version) }

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

      context 'defines :env with missing #env' do
        let(:env_tags) { "env:#{tag_env_value}" }
        let(:tag_env_value) { 'tag-env-value' }

        it 'populates #env from the tag' do
          expect { tags }
            .to change { settings.env }
            .from(nil)
            .to(tag_env_value)
        end
      end

      context 'conflicts with #env' do
        let(:env_tags) { "env:#{tag_env_value}" }
        let(:tag_env_value) { 'tag-env-value' }
        let(:env_value) { 'env-value' }

        before { allow(settings).to receive(:env).and_return(env_value) }

        it { is_expected.to include('env' => env_value) }
      end

      context 'defines :service with missing #service' do
        let(:env_tags) { "service:#{tag_service_value}" }
        let(:tag_service_value) { 'tag-service-value' }

        it 'populates #service from the tag' do
          expect { tags }
            .to change { settings.service }
            .from(nil)
            .to(tag_service_value)
        end
      end

      context 'conflicts with #version' do
        let(:env_tags) { "env:#{tag_version_value}" }
        let(:tag_version_value) { 'tag-version-value' }
        let(:version_value) { 'version-value' }

        before { allow(settings).to receive(:version).and_return(version_value) }

        it { is_expected.to include('version' => version_value) }
      end

      context 'defines :version with missing #version' do
        let(:env_tags) { "version:#{tag_version_value}" }
        let(:tag_version_value) { 'tag-version-value' }

        it 'populates #version from the tag' do
          expect { tags }
            .to change { settings.version }
            .from(nil)
            .to(tag_version_value)
        end
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

  describe '#tracer' do
    context 'old style' do
      context 'given :debug' do
        it 'updates the new #debug setting' do
          expect { settings.tracer(debug: true) }
            .to change { settings.diagnostics.debug }
            .from(false)
            .to(true)
        end
      end

      context 'given :env' do
        let(:env) { 'my-env' }

        it 'updates the new #env setting' do
          expect { settings.tracer env: env }
            .to change { settings.env }
            .from(nil)
            .to(env)
        end
      end

      context 'given :log' do
        let(:custom_log) { Logger.new(STDOUT, level: Logger::INFO) }

        it 'updates the new #instance setting' do
          expect { settings.tracer(log: custom_log) }
            .to change { settings.logger.instance }
            .from(nil)
            .to(custom_log)
        end
      end

      describe 'given :min_spans_before_partial_flush' do
        let(:value) { 1234 }

        it 'updates the new #min_spans_threshold setting' do
          expect { settings.tracer min_spans_before_partial_flush: value }
            .to change { settings.tracer.partial_flush.min_spans_threshold }
            .from(nil)
            .to(value)
        end
      end

      describe 'given :partial_flush' do
        it 'updates the new #enabled setting' do
          expect { settings.tracer partial_flush: true }
            .to change { settings.tracer.partial_flush.enabled }
            .from(false)
            .to(true)
        end
      end

      context 'given :tags' do
        let(:tags) { { 'custom-tag' => 'custom-value' } }

        it 'updates the new #tags setting' do
          expect { settings.tracer tags: tags }
            .to change { settings.tags }
            .from({})
            .to(tags)
        end
      end

      context 'given :writer_options' do
        before { settings.tracer(writer_options: { buffer_size: 1234 }) }

        it 'updates the new #writer_options setting' do
          expect(settings.tracer.writer_options).to eq(buffer_size: 1234)
        end
      end

      context 'given some settings' do
        let(:tracer) { Datadog::Tracer.new }

        before do
          settings.tracer(
            enabled: false,
            hostname: 'tracer.host.com',
            port: 1234,
            env: :config_test,
            tags: { foo: :bar },
            writer_options: { buffer_size: 1234 },
            instance: tracer
          )
        end

        it 'applies settings correctly' do
          expect(settings.tracer.enabled).to be false
          expect(settings.tracer.hostname).to eq('tracer.host.com')
          expect(settings.tracer.port).to eq(1234)
          expect(settings.env).to eq(:config_test)
          expect(settings.tags['foo']).to eq(:bar)
        end
      end

      it 'acts on the tracer option' do
        previous_state = settings.tracer.enabled
        settings.tracer(enabled: !previous_state)
        expect(settings.tracer.enabled).to eq(!previous_state)
        settings.tracer(enabled: previous_state)
        expect(settings.tracer.enabled).to eq(previous_state)
      end
    end

    describe '#enabled' do
      subject(:enabled) { settings.tracer.enabled }
      it { is_expected.to be true }

      context "when #{Datadog::Ext::Diagnostics::DD_TRACE_ENABLED}" do
        around do |example|
          ClimateControl.modify(Datadog::Ext::Diagnostics::DD_TRACE_ENABLED => enable) do
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
        expect { settings.tracer.enabled = false }
          .to change { settings.tracer.enabled }
          .from(true)
          .to(false)
      end
    end

    describe '#hostname' do
      subject(:hostname) { settings.tracer.hostname }
      it { is_expected.to be nil }
    end

    describe '#hostname=' do
      let(:hostname) { 'my-agent' }

      it 'updates the #hostname setting' do
        expect { settings.tracer.hostname = hostname }
          .to change { settings.tracer.hostname }
          .from(nil)
          .to(hostname)
      end
    end

    describe '#instance' do
      subject(:instance) { settings.tracer.instance }
      it { is_expected.to be nil }
    end

    describe '#instance=' do
      let(:tracer) { instance_double(Datadog::Tracer) }

      it 'updates the #instance setting' do
        expect { settings.tracer.instance = tracer }
          .to change { settings.tracer.instance }
          .from(nil)
          .to(tracer)
      end
    end

    describe '#partial_flush' do
      describe '#enabled' do
        subject(:enabled) { settings.tracer.partial_flush.enabled }
        it { is_expected.to be false }
      end

      describe '#enabled=' do
        it 'updates the #enabled setting' do
          expect { settings.tracer.partial_flush.enabled = true }
            .to change { settings.tracer.partial_flush.enabled }
            .from(false)
            .to(true)
        end
      end

      describe '#min_spans_threshold' do
        subject(:min_spans_threshold) { settings.tracer.partial_flush.min_spans_threshold }
        it { is_expected.to be nil }
      end

      describe '#min_spans_threshold=' do
        let(:value) { 1234 }

        it 'updates the #min_spans_before_partial_flush setting' do
          expect { settings.tracer.partial_flush.min_spans_threshold = value }
            .to change { settings.tracer.partial_flush.min_spans_threshold }
            .from(nil)
            .to(value)
        end
      end
    end

    describe '#port' do
      subject(:port) { settings.tracer.port }
      it { is_expected.to be nil }
    end

    describe '#port=' do
      let(:port) { 1234 }

      it 'updates the #port setting' do
        expect { settings.tracer.port = port }
          .to change { settings.tracer.port }
          .from(nil)
          .to(port)
      end
    end

    describe '#priority_sampling' do
      subject(:priority_sampling) { settings.tracer.priority_sampling }
      it { is_expected.to be nil }
    end

    describe '#priority_sampling=' do
      it 'updates the #priority_sampling setting' do
        expect { settings.tracer.priority_sampling = true }
          .to change { settings.tracer.priority_sampling }
          .from(nil)
          .to(true)
      end
    end

    describe '#sampler' do
      subject(:sampler) { settings.tracer.sampler }
      it { is_expected.to be nil }
    end

    describe '#sampler=' do
      let(:sampler) { instance_double(Datadog::PrioritySampler) }

      it 'updates the #sampler setting' do
        expect { settings.tracer.sampler = sampler }
          .to change { settings.tracer.sampler }
          .from(nil)
          .to(sampler)
      end
    end

    describe '#transport_options' do
      subject(:transport_options) { settings.tracer.transport_options }
      it { is_expected.to eq({}) }

      context 'when modified' do
        it 'does not modify the default by reference' do
          settings.tracer.transport_options[:foo] = :bar
          expect(settings.tracer.transport_options).to_not be_empty
          expect(settings.tracer.options[:transport_options].default_value).to be_empty
        end
      end
    end

    describe '#transport_options=' do
      let(:options) { { hostname: 'my-agent' } }

      it 'updates the #transport_options setting' do
        expect { settings.tracer.transport_options = options }
          .to change { settings.tracer.transport_options }
          .from({})
          .to(options)
      end
    end

    describe '#writer' do
      subject(:writer) { settings.tracer.writer }
      it { is_expected.to be nil }
    end

    describe '#writer=' do
      let(:writer) { instance_double(Datadog::Writer) }

      it 'updates the #writer setting' do
        expect { settings.tracer.writer = writer }
          .to change { settings.tracer.writer }
          .from(nil)
          .to(writer)
      end
    end

    describe '#writer_options' do
      subject(:writer_options) { settings.tracer.writer_options }
      it { is_expected.to eq({}) }

      context 'when modified' do
        it 'does not modify the default by reference' do
          settings.tracer.writer_options[:foo] = :bar
          expect(settings.tracer.writer_options).to_not be_empty
          expect(settings.tracer.options[:writer_options].default_value).to be_empty
        end
      end
    end

    describe '#writer_options=' do
      let(:options) { { priority_sampling: true } }

      it 'updates the #writer_options setting' do
        expect { settings.tracer.writer_options = options }
          .to change { settings.tracer.writer_options }
          .from({})
          .to(options)
      end
    end
  end

  describe '#tracer=' do
    let(:tracer) { instance_double(Datadog::Tracer) }

    it 'sets the tracer instance' do
      expect { settings.tracer = tracer }.to change { settings.tracer.instance }
        .from(nil)
        .to(tracer)
    end
  end

  describe '#version' do
    subject(:version) { settings.version }
    context "when #{Datadog::Ext::Environment::ENV_VERSION}" do
      around do |example|
        ClimateControl.modify(Datadog::Ext::Environment::ENV_VERSION => version) do
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
