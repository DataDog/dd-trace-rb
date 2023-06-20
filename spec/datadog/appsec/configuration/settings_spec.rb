require 'datadog/appsec/spec_helper'

# Dummy Integration
class FakeIntegration
  module Patcher
    module_function

    def patched?
      @patched
    end

    def patch
      @patched = true
    end

    def reset
      @patched = nil
    end
  end

  def self.loaded?
    true
  end

  def self.compatible?
    true
  end

  def self.auto_instrument?
    false
  end

  def patcher
    Patcher
  end
end

RSpec.describe Datadog::AppSec::Configuration::Settings do
  let(:registry) { {} }
  let(:dsl) { Datadog::AppSec::Configuration::DSL.new }
  let(:integration_name) { :fake }

  after do
    FakeIntegration::Patcher.reset
    settings.send(:reset!)
  end

  before do
    registry[integration_name] = instance_double(
      Datadog::AppSec::Contrib::Integration::RegisteredIntegration,
      klass: FakeIntegration,
    )

    allow(Datadog::AppSec::Contrib::Integration).to receive(:registry).and_return(registry)
  end

  subject(:settings) { described_class.new }

  describe '#enabled' do
    subject(:enabled) { settings.enabled }
    it { is_expected.to eq(false) }
  end

  describe '#enabled=' do
    subject(:enabled_) { settings.merge(dsl.tap { |c| c.enabled = true }) }
    it { expect { enabled_ }.to change { settings.enabled }.from(false).to(true) }
  end

  describe '#ruleset' do
    subject(:ruleset) { settings.ruleset }
    it { is_expected.to eq(:recommended) }
  end

  describe '#ruleset=' do
    subject(:ruleset_) { settings.merge(dsl.tap { |c| c.ruleset = :strict }) }
    it { expect { ruleset_ }.to change { settings.ruleset }.from(:recommended).to(:strict) }
  end

  describe '#waf_timeout' do
    subject(:waf_timeout) { settings.waf_timeout }
    it { is_expected.to eq(5000) }
  end

  describe '#waf_timeout=' do
    subject(:waf_timeout_) { settings.merge(dsl.tap { |c| c.waf_timeout = 3 }) }
    it { expect { waf_timeout_ }.to change { settings.waf_timeout }.from(5000).to(3) }
  end

  describe '#waf_debug' do
    subject(:waf_debug) { settings.waf_debug }
    it { is_expected.to eq(false) }
  end

  describe '#waf_debug=' do
    subject(:waf_debug_) { settings.merge(dsl.tap { |c| c.waf_debug = true }) }
    it { expect { waf_debug_ }.to change { settings.waf_debug }.from(false).to(true) }
  end

  describe '#trace_rate_limit' do
    subject(:trace_rate_limit) { settings.trace_rate_limit }
    it { is_expected.to eq(100) }
  end

  describe '#trace_rate_limit=' do
    subject(:trace_rate_limit_) { settings.merge(dsl.tap { |c| c.trace_rate_limit = 2 }) }
    it { expect { trace_rate_limit_ }.to change { settings.trace_rate_limit }.from(100).to(2) }
  end

  describe '#ip_denylist' do
    subject(:ip_denylist) { settings.ip_denylist }
    it { is_expected.to eq([]) }
  end

  describe '#ip_denylist=' do
    subject(:ip_denylist_) { settings.merge(dsl.tap { |c| c.ip_denylist = ['192.192.1.1'] }) }
    it { expect { ip_denylist_ }.to change { settings.ip_denylist }.from([]).to(['192.192.1.1']) }
  end

  describe '#user_id_denylist' do
    subject(:user_id_denylist) { settings.user_id_denylist }
    it { is_expected.to eq([]) }
  end

  describe '#user_id_denylist=' do
    subject(:user_id_denylist_) { settings.merge(dsl.tap { |c| c.user_id_denylist = ['8764937902709'] }) }
    it { expect { user_id_denylist_ }.to change { settings.user_id_denylist }.from([]).to(['8764937902709']) }
  end

  describe '#obfuscator_key_regex' do
    subject(:obfuscator_key_regex) { settings.obfuscator_key_regex }
    it { is_expected.to include('token') }
  end

  describe '#obfuscator_key_regex=' do
    subject(:obfuscator_key_regex_) { settings.merge(dsl.tap { |c| c.obfuscator_key_regex = 'bar' }) }
    let(:default) { described_class::DEFAULT_OBFUSCATOR_KEY_REGEX }
    it { expect { obfuscator_key_regex_ }.to change { settings.obfuscator_key_regex }.from(default).to('bar') }
  end

  describe '#obfuscator_value_regex' do
    subject(:obfuscator_value_regex) { settings.obfuscator_value_regex }
    it { is_expected.to include('token') }
  end

  describe '#obfuscator_value_regex=' do
    subject(:obfuscator_value_regex_) { settings.merge(dsl.tap { |c| c.obfuscator_value_regex = 'bar' }) }
    let(:default) { described_class::DEFAULT_OBFUSCATOR_VALUE_REGEX }
    it { expect { obfuscator_value_regex_ }.to change { settings.obfuscator_value_regex }.from(default).to('bar') }
  end

  describe '#integrations' do
    context 'appsec enabled' do
      before { dsl.enabled = true }

      context 'when loaded and compatible' do
        it 'patches the integration' do
          dsl.instrument(integration_name)

          expect(FakeIntegration::Patcher).to receive(:patch)

          settings.merge(dsl)
        end
      end

      context 'only patches integration once' do
        it 'does not patch the integration multiple times' do
          dsl.instrument(integration_name)

          expect(FakeIntegration::Patcher).to receive(:patch).and_call_original.once
          settings.merge(dsl)
          settings.merge(dsl)
        end
      end

      context 'when not loaded' do
        before { expect(FakeIntegration).to receive(:loaded?).and_return(false) }
        it 'does not patch the integration' do
          dsl.instrument(integration_name)

          expect(FakeIntegration::Patcher).to_not receive(:patch)

          settings.merge(dsl)
        end
      end

      context 'when loaded and not compatible' do
        before { expect(FakeIntegration).to receive(:compatible?).and_return(false) }
        it 'does not patch the integration' do
          dsl.instrument(integration_name)

          expect(FakeIntegration::Patcher).to_not receive(:patch)

          settings.merge(dsl)
        end
      end

      context 'when integration does not exists' do
        it 'does not patch the integration' do
          dsl.instrument(:not_exiting)

          expect { settings.merge(dsl) }.to_not raise_error
        end
      end
    end

    context 'appsec is not enabled' do
      it 'does not patch the integration multiple times' do
        dsl.instrument(integration_name)

        expect(FakeIntegration::Patcher).to_not receive(:patch)
        settings.merge(dsl)
      end
    end
  end

  context 'with env vars' do
    describe 'DD_APPSEC_ENABLED' do
      around do |example|
        ClimateControl.modify('DD_APPSEC_ENABLED' => '1') do
          example.run
        end
      end

      describe '#enabled' do
        subject(:enabled) { settings.enabled }
        it { is_expected.to eq(true) }
      end

      describe '#enabled=' do
        subject(:enabled_) { settings.merge(dsl.tap { |c| c.enabled = false }) }
        it { expect { enabled_ }.to change { settings.enabled }.from(true).to(false) }
      end
    end

    describe 'DD_APPSEC_RULES' do
      around do |example|
        ClimateControl.modify('DD_APPSEC_RULES' => '/some/path') do
          example.run
        end
      end

      describe '#ruleset' do
        subject(:ruleset) { settings.ruleset }
        it { is_expected.to eq('/some/path') }
      end

      describe '#ruleset=' do
        subject(:ruleset_) { settings.merge(dsl.tap { |c| c.ruleset = :strict }) }
        it { expect { ruleset_ }.to change { settings.ruleset }.from('/some/path').to(:strict) }
      end
    end

    describe 'DD_APPSEC_WAF_TIMEOUT' do
      around do |example|
        ClimateControl.modify('DD_APPSEC_WAF_TIMEOUT' => '42') do
          example.run
        end
      end

      describe '#waf_timeout' do
        subject(:waf_timeout) { settings.waf_timeout }
        it { is_expected.to eq(42) }
      end

      describe '#waf_timeout=' do
        subject(:waf_timeout_) { settings.merge(dsl.tap { |c| c.waf_timeout = 3 }) }
        it { expect { waf_timeout_ }.to change { settings.waf_timeout }.from(42).to(3) }
      end
    end

    describe 'DD_APPSEC_WAF_DEBUG' do
      around do |example|
        ClimateControl.modify('DD_APPSEC_WAF_DEBUG' => '1') do
          example.run
        end
      end

      describe '#waf_debug' do
        subject(:waf_debug) { settings.waf_debug }
        it { is_expected.to eq(true) }
      end

      describe '#waf_debug=' do
        subject(:waf_debug_) { settings.merge(dsl.tap { |c| c.waf_debug = false }) }
        it { expect { waf_debug_ }.to change { settings.waf_debug }.from(true).to(false) }
      end
    end

    describe 'DD_APPSEC_TRACE_RATE_LIMIT' do
      around do |example|
        ClimateControl.modify('DD_APPSEC_TRACE_RATE_LIMIT' => '1024') do
          example.run
        end
      end

      describe '#trace_rate_limit' do
        subject(:trace_rate_limit) { settings.trace_rate_limit }
        it { is_expected.to eq(1024) }
      end

      describe '#trace_rate_limit=' do
        subject(:trace_rate_limit_) { settings.merge(dsl.tap { |c| c.trace_rate_limit = 2 }) }
        it { expect { trace_rate_limit_ }.to change { settings.trace_rate_limit }.from(1024).to(2) }
      end
    end

    describe 'DD_APPSEC_OBFUSCATION_PARAMETER_KEY_REGEXP' do
      around do |example|
        ClimateControl.modify('DD_APPSEC_OBFUSCATION_PARAMETER_KEY_REGEXP' => 'bar') do
          example.run
        end
      end

      describe '#obfuscator_key_regex' do
        subject(:obfuscator_key_regex) { settings.obfuscator_key_regex }
        it { is_expected.to eq('bar') }
      end

      describe '#obfuscator_key_regex=' do
        subject(:obfuscator_key_regex_) { settings.merge(dsl.tap { |c| c.obfuscator_key_regex = 'baz' }) }
        it { expect { obfuscator_key_regex_ }.to change { settings.obfuscator_key_regex }.from('bar').to('baz') }
      end
    end

    describe 'DD_APPSEC_OBFUSCATION_PARAMETER_VALUE_REGEXP' do
      around do |example|
        ClimateControl.modify('DD_APPSEC_OBFUSCATION_PARAMETER_VALUE_REGEXP' => 'bar') do
          example.run
        end
      end

      describe '#obfuscator_value_regex' do
        subject(:obfuscator_value_regex) { settings.obfuscator_value_regex }
        it { is_expected.to eq('bar') }
      end

      describe '#obfuscator_value_regex=' do
        subject(:obfuscator_value_regex_) { settings.merge(dsl.tap { |c| c.obfuscator_value_regex = 'baz' }) }
        it { expect { obfuscator_value_regex_ }.to change { settings.obfuscator_value_regex }.from('bar').to('baz') }
      end
    end

    describe '#default?' do
      context 'when the configuration option is configured via ENV var' do
        around do |example|
          ClimateControl.modify('DD_APPSEC_ENABLED' => '1') do
            example.run
          end
        end

        it 'returns false' do
          expect(settings.send(:default?, :enabled)).to eq(false)
        end
      end

      context 'when the configuration option is configured via merge' do
        before do
          settings.merge(dsl.tap { |c| c.enabled = true })
        end

        it 'returns false' do
          expect(settings.send(:default?, :enabled)).to eq(false)
        end
      end

      context 'when the configuration option is not configured' do
        it 'returns true' do
          expect(settings.send(:default?, :enabled)).to eq(true)
        end
      end
    end
  end
end
