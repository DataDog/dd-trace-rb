require 'spec_helper'

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
  subject(:settings) { Datadog::Core::Configuration::Settings.new }

  describe 'appsec' do
    describe '#enabled' do
      subject(:enabled) { settings.appsec.enabled }

      context 'when DD_APPSEC_ENABLED' do
        around do |example|
          ClimateControl.modify('DD_APPSEC_ENABLED' => appsec_enabled) do
            example.run
          end
        end

        context 'is not defined' do
          let(:appsec_enabled) { nil }

          it { is_expected.to be described_class::DEFAULT_APPSEC_ENABLED }
        end

        context 'is defined' do
          let(:appsec_enabled) { 'true' }

          it { is_expected.to eq(true) }
        end
      end
    end

    describe '#enabled=' do
      subject(:set_appsec_enabled) { settings.appsec.enabled = appsec_enabled }

      context 'when given a falsy value' do
        let(:appsec_enabled) { nil }

        before { set_appsec_enabled }

        it { expect(settings.appsec.enabled).to eq(false) }
      end

      context 'when given a truthy value' do
        let(:appsec_enabled) { 'enabled' }

        before { set_appsec_enabled }

        it { expect(settings.appsec.enabled).to eq(true) }
      end
    end

    describe '#instrument' do
      let(:registry) { {} }
      let(:integration_name) { :fake }
      subject(:instrument) { settings.appsec.instrument(integration_name) }

      before do
        registry[integration_name] = instance_double(
          Datadog::AppSec::Contrib::Integration::RegisteredIntegration,
          klass: FakeIntegration,
        )

        allow(Datadog::AppSec::Contrib::Integration).to receive(:registry).and_return(registry)
        settings.appsec.enabled = appsec_enabled
      end

      after do
        FakeIntegration::Patcher.reset
      end

      context 'appsec enabled' do
        let(:appsec_enabled) { true }
        context 'when integration exists' do
          context 'when loaded and compatible' do
            it 'patches the integration' do
              expect(FakeIntegration::Patcher).to receive(:patch)

              instrument
            end
          end

          context 'only patches integration once' do
            it 'does not patch the integration multiple times' do
              expect(FakeIntegration::Patcher).to receive(:patch).and_call_original.once

              instrument
              instrument
            end
          end

          context 'when not loaded' do
            before { expect(FakeIntegration).to receive(:loaded?).and_return(false) }
            it 'does not patch the integration' do
              expect(FakeIntegration::Patcher).to_not receive(:patch)

              instrument
            end
          end

          context 'when loaded and not compatible' do
            before { expect(FakeIntegration).to receive(:compatible?).and_return(false) }
            it 'does not patch the integration' do
              expect(FakeIntegration::Patcher).to_not receive(:patch)

              instrument
            end
          end

          context 'when integration does not exists' do
            let(:integration_name) { :not_exiting }
            it 'does not patch the integration' do
              expect { instrument }.to_not raise_error
            end
          end
        end

        context 'appsec is not enabled' do
          let(:appsec_enabled) { false }

          it 'does not patch the integration multiple times' do
            expect(FakeIntegration::Patcher).to_not receive(:patch)
            instrument
          end
        end
      end
    end

    describe '#ruleset' do
      subject(:ruleset) { settings.appsec.ruleset }

      context 'when DD_APPSEC_RULES' do
        around do |example|
          ClimateControl.modify('DD_APPSEC_RULES' => appsec_ruleset) do
            example.run
          end
        end

        context 'is not defined' do
          let(:appsec_ruleset) { nil }

          it { is_expected.to be described_class::DEFAULT_APPSEC_RULESET }
        end

        context 'is defined' do
          let(:appsec_ruleset) { 'something' }

          it { is_expected.to eq('something') }
        end
      end
    end

    describe '#ruleset=' do
      subject(:set_appsec_ruleset) { settings.appsec.ruleset = appsec_ruleset }

      context 'when given a value' do
        let(:appsec_ruleset) { nil }

        before { set_appsec_ruleset }

        it { expect(settings.appsec.ruleset).to eq(nil) }
      end
    end

    describe '#ip_denylist' do
      subject(:ip_denylist) { settings.appsec.ip_denylist }

      context 'default value' do
        it { is_expected.to eq [] }
      end
    end

    describe '#ip_denylist=' do
      subject(:set_appsec_ip_denylist) { settings.appsec.ip_denylist = appsec_ip_denylist }

      context 'when given a value' do
        let(:appsec_ip_denylist) { ['1.1.1.1'] }

        before { set_appsec_ip_denylist }

        it { expect(settings.appsec.ip_denylist).to eq(['1.1.1.1']) }
      end
    end

    describe '#user_id_denylist' do
      subject(:user_id_denylist) { settings.appsec.user_id_denylist }

      context 'default value' do
        it { is_expected.to eq [] }
      end
    end

    describe '#user_id_denylist=' do
      subject(:set_appsec_user_id_denylist) { settings.appsec.user_id_denylist = appsec_user_id_denylist }

      context 'when given a value' do
        let(:appsec_user_id_denylist) { ['1'] }

        before { set_appsec_user_id_denylist }

        it { expect(settings.appsec.user_id_denylist).to eq(['1']) }
      end
    end

    describe '#waf_timeout' do
      subject(:waf_timeout) { settings.appsec.waf_timeout }

      context 'when DD_APPSEC_WAF_TIMEOUT' do
        around do |example|
          ClimateControl.modify('DD_APPSEC_WAF_TIMEOUT' => appsec_waf_timeout) do
            example.run
          end
        end

        context 'is not defined' do
          let(:appsec_waf_timeout) { nil }

          it { is_expected.to be described_class::DEFAULT_APPSEC_WAF_TIMEOUT }
        end

        context 'is defined' do
          let(:appsec_waf_timeout) { '2000' }

          it { is_expected.to eq(2000) }
        end

        context 'is defined as a float' do
          let(:appsec_waf_timeout) { '2.5' }

          it { is_expected.to eq(3) }
        end

        context 'is defined with custom suffix' do
          let(:appsec_waf_timeout) { '2000s' }

          it { is_expected.to eq(2000000000) }
        end

        context 'is defined as a float with custom suffix' do
          let(:appsec_waf_timeout) { '2.5m' }

          it { is_expected.to eq(150000000) }
        end
      end
    end

    describe '#waf_timeout=' do
      subject(:set_appsec_waf_timeout) { settings.appsec.waf_timeout = appsec_waf_timeout }
      before { set_appsec_waf_timeout }

      context 'when given a value' do
        let(:appsec_waf_timeout) { 1000 }

        it { expect(settings.appsec.waf_timeout).to eq(1000) }
      end

      context 'when given a value with custom suffix' do
        let(:appsec_waf_timeout) { '1000h' }

        it { expect(settings.appsec.waf_timeout).to eq(3600000000000) }
      end

      context 'is defined as a float' do
        let(:appsec_waf_timeout) { '2.5' }

        it { expect(settings.appsec.waf_timeout).to eq(3) }
      end

      context 'is defined as a float with custom suffix' do
        let(:appsec_waf_timeout) { '2.5m' }

        it { expect(settings.appsec.waf_timeout).to eq(150000000) }
      end
    end

    describe '#waf_debug' do
      subject(:waf_debug) { settings.appsec.waf_debug }

      context 'when DD_APPSEC_WAF_DEBUG' do
        around do |example|
          ClimateControl.modify('DD_APPSEC_WAF_DEBUG' => appsec_waf_debug) do
            example.run
          end
        end

        context 'is not defined' do
          let(:appsec_waf_debug) { nil }

          it { is_expected.to be described_class::DEFAULT_APPSEC_WAF_DEBUG }
        end

        context 'is defined' do
          let(:appsec_waf_debug) { 'true' }

          it { is_expected.to eq(true) }
        end
      end
    end

    describe '#waf_debug=' do
      subject(:set_appsec_waf_debug) { settings.appsec.waf_debug = appsec_waf_debug }

      context 'when given a falsy value' do
        let(:appsec_waf_debug) { nil }

        before { set_appsec_waf_debug }

        it { expect(settings.appsec.waf_debug).to eq(false) }
      end

      context 'when given a truthy value' do
        let(:appsec_waf_debug) { 'waf_debug' }

        before { set_appsec_waf_debug }

        it { expect(settings.appsec.waf_debug).to eq(true) }
      end
    end

    describe '#trace_rate_limit' do
      subject(:trace_rate_limit) { settings.appsec.trace_rate_limit }

      context 'when DD_APPSEC_TRACE_RATE_LIMIT' do
        around do |example|
          ClimateControl.modify('DD_APPSEC_TRACE_RATE_LIMIT' => appsec_trace_rate_limit) do
            example.run
          end
        end

        context 'is not defined' do
          let(:appsec_trace_rate_limit) { nil }

          it { is_expected.to be described_class::DEFAULT_APPSEC_TRACE_RATE_LIMIT }
        end

        context 'is defined' do
          let(:appsec_trace_rate_limit) { '2000' }

          it { is_expected.to eq(2000) }
        end
      end
    end

    describe '#trace_rate_limit=' do
      subject(:set_appsec_trace_rate_limit) { settings.appsec.trace_rate_limit = appsec_trace_rate_limit }

      context 'when given a value' do
        let(:appsec_trace_rate_limit) { 1000 }

        before { set_appsec_trace_rate_limit }

        it { expect(settings.appsec.trace_rate_limit).to eq(1000) }
      end
    end

    describe '#obfuscator_key_regex' do
      subject(:obfuscator_key_regex) { settings.appsec.obfuscator_key_regex }

      context 'when DD_APPSEC_OBFUSCATION_PARAMETER_KEY_REGEXP' do
        around do |example|
          ClimateControl.modify('DD_APPSEC_OBFUSCATION_PARAMETER_KEY_REGEXP' => appsec_obfuscator_key_regex) do
            example.run
          end
        end

        context 'is not defined' do
          let(:appsec_obfuscator_key_regex) { nil }

          it { is_expected.to be described_class::DEFAULT_OBFUSCATOR_KEY_REGEX }
        end

        context 'is defined' do
          let(:appsec_obfuscator_key_regex) { 'random value' }

          it { is_expected.to eq('random value') }
        end
      end
    end

    describe '#obfuscator_key_regex=' do
      subject(:set_appsec_obfuscator_key_regex) { settings.appsec.obfuscator_key_regex = appsec_obfuscator_key_regex }

      context 'when given a value' do
        let(:appsec_obfuscator_key_regex) { 'random value' }

        before { set_appsec_obfuscator_key_regex }

        it { expect(settings.appsec.obfuscator_key_regex).to eq('random value') }
      end
    end

    describe '#obfuscator_value_regex' do
      subject(:obfuscator_value_regex) { settings.appsec.obfuscator_value_regex }

      context 'when DD_APPSEC_OBFUSCATION_PARAMETER_VALUE_REGEXP' do
        around do |example|
          ClimateControl.modify('DD_APPSEC_OBFUSCATION_PARAMETER_VALUE_REGEXP' => appsec_obfuscator_value_regex) do
            example.run
          end
        end

        context 'is not defined' do
          let(:appsec_obfuscator_value_regex) { nil }

          it { is_expected.to be described_class::DEFAULT_OBFUSCATOR_VALUE_REGEX }
        end

        context 'is defined' do
          let(:appsec_obfuscator_value_regex) { 'random value' }

          it { is_expected.to eq('random value') }
        end
      end
    end

    describe '#obfuscator_value_regex=' do
      subject(:set_appsec_obfuscator_value_regex) { settings.appsec.obfuscator_value_regex = appsec_obfuscator_value_regex }

      context 'when given a value' do
        let(:appsec_obfuscator_value_regex) { 'random value' }

        before { set_appsec_obfuscator_value_regex }

        it { expect(settings.appsec.obfuscator_value_regex).to eq('random value') }
      end
    end

    describe 'track_user_events' do
      describe '#enabled' do
        subject(:enabled) { settings.appsec.track_user_events.enabled }

        context 'when DD_APPSEC_AUTOMATED_USER_EVENTS_TRACKING' do
          around do |example|
            ClimateControl.modify('DD_APPSEC_AUTOMATED_USER_EVENTS_TRACKING' => track_user_events_enabled) do
              example.run
            end
          end

          context 'is not defined' do
            let(:track_user_events_enabled) { nil }

            it { is_expected.to be described_class::DEFAULT_APPSEC_AUTOMATED_TRACK_USER_EVENTS_ENABLED }
          end

          context 'is defined' do
            context 'value other than disabled' do
              let(:track_user_events_enabled) { 'true' }

              it { is_expected.to eq(true) }
            end

            context 'value equal to disabled' do
              let(:track_user_events_enabled) { 'disabled' }

              it { is_expected.to eq(false) }
            end
          end
        end
      end

      describe '#enabled=' do
        subject(:set_appsec_track_user_events_enabled) do
          settings.appsec.track_user_events.enabled = track_user_events_enabled
        end

        context 'when given a falsy value' do
          let(:track_user_events_enabled) { nil }

          before { set_appsec_track_user_events_enabled }

          it { expect(settings.appsec.track_user_events.enabled).to eq(false) }
        end

        context 'when given a truthy value' do
          let(:track_user_events_enabled) { 'enabled' }

          before { set_appsec_track_user_events_enabled }

          it { expect(settings.appsec.track_user_events.enabled).to eq(true) }
        end
      end

      describe '#mode' do
        subject(:mode) { settings.appsec.track_user_events.mode }

        context 'when DD_APPSEC_AUTOMATED_USER_EVENTS_TRACKING' do
          around do |example|
            ClimateControl.modify('DD_APPSEC_AUTOMATED_USER_EVENTS_TRACKING' => track_user_events_mode) do
              example.run
            end
          end

          context 'is not defined' do
            let(:track_user_events_mode) { nil }

            it { is_expected.to be described_class::DEFAULT_APPSEC_AUTOMATED_TRACK_USER_EVENTS_MODE }
          end

          context 'is defined' do
            context 'value other than disabled and supported' do
              let(:track_user_events_mode) { 'extended' }

              it { is_expected.to eq('extended') }
            end

            context 'value equal to disabled' do
              let(:track_user_events_mode) { 'disabled' }

              it { is_expected.to eq(described_class::DEFAULT_APPSEC_AUTOMATED_TRACK_USER_EVENTS_MODE) }
            end
          end
        end
      end

      describe '#mode=' do
        subject(:set_appsec_track_user_events_mode) do
          settings.appsec.track_user_events.mode = track_user_events_mode
        end

        context 'when given a supported value' do
          let(:track_user_events_mode) { :extended }

          before { set_appsec_track_user_events_mode }

          it { expect(settings.appsec.track_user_events.mode).to eq('extended') }
        end

        context 'when given a non supported value' do
          let(:track_user_events_mode) { 'mode' }

          before { set_appsec_track_user_events_mode }

          it {
            expect(settings.appsec.track_user_events.mode).to eq(
              described_class::DEFAULT_APPSEC_AUTOMATED_TRACK_USER_EVENTS_MODE
            )
          }
        end
      end
    end
  end
end
