require 'spec_helper'

require 'ddtrace'
require 'ddtrace/configuration/settings'

RSpec.describe Datadog::Configuration::Settings do
  subject(:settings) { described_class.new }

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

      context 'conflicts with #env' do
        let(:env_tags) { "env:#{tag_env_value}" }
        let(:tag_env_value) { 'tag-env-value' }
        let(:env_value) { 'env-value' }

        before { allow(settings).to receive(:env).and_return(env_value) }

        it { is_expected.to include('env' => env_value) }
      end

      context 'conflicts with #version' do
        let(:env_tags) { "env:#{tag_version_value}" }
        let(:tag_version_value) { 'tag-version-value' }
        let(:version_value) { 'version-value' }

        before { allow(settings).to receive(:version).and_return(version_value) }

        it { is_expected.to include('version' => version_value) }
      end
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

  describe '#sampling' do
    describe '#rate_limit' do
      subject(:rate_limit) { settings.sampling.rate_limit }

      context 'default' do
        it { is_expected.to be 100 }
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

  describe '#tracer' do
    context 'given :log' do
      let(:custom_log) { Logger.new(STDOUT, level: Logger::INFO) }

      before do
        @original_log = Datadog::Logger.log
        settings.tracer(log: custom_log)
      end

      after do
        Datadog::Logger.log = @original_log
      end

      it 'uses the logger for logging' do
        expect(Datadog::Logger.log).to eq(custom_log)
      end
    end

    context 'given :debug' do
      subject(:configure) { settings.tracer(debug: debug) }

      shared_examples_for 'debug toggle' do
        before { Datadog::Logger.debug_logging = !debug }
        after { Datadog::Logger.debug_logging = false }

        it do
          expect { configure }.to change { Datadog::Logger.debug_logging }
            .from(!debug)
            .to(debug)
        end
      end

      context 'as true' do
        it_behaves_like 'debug toggle' do
          let(:debug) { true }
        end
      end

      context 'as false' do
        it_behaves_like 'debug toggle' do
          let(:debug) { false }
        end
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

      after do
        Datadog::Logger.debug_logging = false
      end

      it 'applies settings correctly' do
        expect(tracer.enabled).to be false
        expect(tracer.writer.transport.current_api.adapter.hostname).to eq('tracer.host.com')
        expect(tracer.writer.transport.current_api.adapter.port).to eq(1234)
        expect(tracer.tags['env']).to eq(:config_test)
        expect(tracer.tags['foo']).to eq(:bar)
      end
    end

    context 'given :writer_options' do
      before { settings.tracer(writer_options: { buffer_size: 1234 }) }

      it 'applies settings correctly' do
        expect(settings.tracer.writer.instance_variable_get(:@buff_size)).to eq(1234)
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
end
