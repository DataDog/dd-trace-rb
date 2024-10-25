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

          it { is_expected.to eq false }
        end

        context 'is defined' do
          let(:appsec_enabled) { 'true' }

          it { is_expected.to eq(true) }
        end
      end
    end

    describe '#enabled=' do
      subject(:set_appsec_enabled) { settings.appsec.enabled = appsec_enabled }

      [true, false].each do |value|
        context "when given #{value}" do
          let(:appsec_enabled) { value }

          before { set_appsec_enabled }

          it { expect(settings.appsec.enabled).to eq(value) }
        end
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

          it { is_expected.to eq :recommended }
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

          it { is_expected.to eq 5000 }
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

          it { is_expected.to eq false }
        end

        context 'is defined' do
          let(:appsec_waf_debug) { 'true' }

          it { is_expected.to eq(true) }
        end
      end
    end

    describe '#waf_debug=' do
      subject(:set_appsec_waf_debug) { settings.appsec.waf_debug = appsec_waf_debug }

      [true, false].each do |value|
        context "when given #{value}" do
          let(:appsec_waf_debug) { value }

          before { set_appsec_waf_debug }

          it { expect(settings.appsec.waf_debug).to eq(value) }
        end
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

          it { is_expected.to eq 100 }
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

          it { is_expected.to eq described_class::DEFAULT_OBFUSCATOR_KEY_REGEX }
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

          it { is_expected.to eq described_class::DEFAULT_OBFUSCATOR_VALUE_REGEX }
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

            it { is_expected.to eq true }
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

            context 'using the mode values: extended | safe' do
              ['extended', 'safe'].each do |value|
                let(:track_user_events_enabled) { value }

                it { is_expected.to eq(true) }
              end
            end
          end
        end
      end

      describe '#enabled=' do
        subject(:set_appsec_track_user_events_enabled) do
          settings.appsec.track_user_events.enabled = track_user_events_enabled
        end

        [true, false].each do |value|
          context "when given #{value}" do
            let(:track_user_events_enabled) { value }

            before { set_appsec_track_user_events_enabled }

            it { expect(settings.appsec.track_user_events.enabled).to eq(value) }
          end
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

            it { is_expected.to eq 'safe' }
          end

          context 'is defined' do
            context 'value other than disabled and supported' do
              let(:track_user_events_mode) { 'extended' }

              it { is_expected.to eq('extended') }
            end

            context 'value equal to disabled' do
              let(:track_user_events_mode) { 'disabled' }

              it { is_expected.to eq 'safe' }
            end
          end
        end
      end

      describe '#mode=' do
        subject(:set_appsec_track_user_events_mode) do
          settings.appsec.track_user_events.mode = track_user_events_mode
        end

        context 'when given a supported value' do
          let(:track_user_events_mode) { 'extended' }

          before { set_appsec_track_user_events_mode }

          it { expect(settings.appsec.track_user_events.mode).to eq('extended') }
        end

        context 'when given a non supported value' do
          let(:track_user_events_mode) { 'mode' }

          before { set_appsec_track_user_events_mode }

          it {
            expect(settings.appsec.track_user_events.mode).to eq('safe')
          }
        end
      end
    end

    describe 'block' do
      describe 'templates' do
        [
          { method_name: :html, env_var: 'DD_APPSEC_HTTP_BLOCKED_TEMPLATE_HTML' },
          { method_name: :json, env_var: 'DD_APPSEC_HTTP_BLOCKED_TEMPLATE_JSON' },
          { method_name: :text, env_var: 'DD_APPSEC_HTTP_BLOCKED_TEMPLATE_TEXT' }
        ].each do |test_info|
          describe "##{test_info[:method_name]}" do
            context "when #{test_info[:env_var]}" do
              subject(:template) { settings.appsec.block.templates.send(test_info[:method_name]) }

              around do |example|
                ClimateControl.modify(test_info[:env_var] => template_path) do
                  example.run
                end
              end

              context 'is defined and the file exists' do
                before do
                  File.write(template_path, 'testing')
                end

                after do
                  File.delete(template_path)
                end

                let(:template_path) do
                  "hello.#{test_info[:method_name]}"
                end

                it { is_expected.to eq 'testing' }
              end

              context 'is defined and the file do not exists' do
                let(:template_path) do
                  "hello.#{test_info[:method_name]}"
                end

                it { expect { is_expected }.to raise_error(ArgumentError) }
              end
            end
          end

          describe "##{test_info[:method_name]}=" do
            subject(:template) { settings.appsec.block.templates.send("#{test_info[:method_name]}=", template_path) }

            context 'is defined and the file exists' do
              before do
                File.write(template_path, 'testing')
              end

              after do
                File.delete(template_path)
              end

              let(:template_path) do
                "hello.#{test_info[:method_name]}"
              end

              it { is_expected.to eq 'testing' }
            end

            context 'is defined and the file do not exists' do
              let(:template_path) do
                "hello.#{test_info[:method_name]}"
              end

              it { expect { is_expected }.to raise_error(ArgumentError) }
            end
          end
        end
      end
    end

    describe 'api_security' do
      describe '#enabled' do
        subject(:enabled) { settings.appsec.api_security.enabled }

        context 'when DD_EXPERIMENTAL_API_SECURITY_ENABLED' do
          around do |example|
            ClimateControl.modify('DD_EXPERIMENTAL_API_SECURITY_ENABLED' => api_security_enabled) do
              example.run
            end
          end

          context 'is not defined' do
            let(:api_security_enabled) { nil }

            it { is_expected.to eq false }
          end

          context 'is defined' do
            let(:api_security_enabled) { 'true' }

            it { is_expected.to eq(true) }
          end
        end
      end

      describe '#enabled=' do
        subject(:set_api_security_enabled) { settings.appsec.api_security.enabled = api_security_enabled }

        [true, false].each do |value|
          context "when given #{value}" do
            let(:api_security_enabled) { value }

            before { set_api_security_enabled }

            it { expect(settings.appsec.api_security.enabled).to eq(value) }
          end
        end
      end

      describe '#sample_rate' do
        subject(:sample_rate) { settings.appsec.api_security.sample_rate.rate }

        context 'when DD_API_SECURITY_REQUEST_SAMPLE_RATE' do
          around do |example|
            ClimateControl.modify('DD_API_SECURITY_REQUEST_SAMPLE_RATE' => api_security_sample_rate) do
              example.run
            end
          end

          context 'is not defined' do
            let(:api_security_sample_rate) { nil }

            it { is_expected.to eq 0.1 }
          end

          context 'is defined' do
            let(:api_security_sample_rate) { '0.3' }

            it { is_expected.to eq 0.3 }
          end
        end
      end

      describe '#sample_rate=' do
        subject(:set_api_security_sample_rate) do
          settings.appsec.api_security.sample_rate = api_security_sample_rate
        end

        context 'when given a value higher than 1.0' do
          let(:api_security_sample_rate) { 1.2 }

          before { set_api_security_sample_rate }

          it { expect(settings.appsec.api_security.sample_rate.rate).to eq 1.0 }
        end
      end
    end

    describe 'sca' do
      describe '#enabled' do
        subject(:sca_enabled) { settings.appsec.sca_enabled }

        context 'when DD_APPSEC_SCA_ENABLED' do
          around do |example|
            ClimateControl.modify('DD_APPSEC_SCA_ENABLED' => sca_enabled_value) do
              example.run
            end
          end

          context 'is not defined' do
            let(:sca_enabled_value) { nil }

            it { is_expected.to eq nil }
          end

          context 'is defined as true' do
            let(:sca_enabled_value) { 'true' }

            it { is_expected.to eq true }
          end

          context 'is defined as false' do
            let(:sca_enabled_value) { 'false' }

            it { is_expected.to eq false }
          end
        end
      end

      describe '#enabled=' do
        subject(:set_sca_enabled) { settings.appsec.sca_enabled = sca_enabled }

        [true, false, nil].each do |value|
          context "when given #{value}" do
            let(:sca_enabled) { value }

            before { set_sca_enabled }

            it { expect(settings.appsec.sca_enabled).to eq(value) }
          end
        end
      end
    end

    describe 'standalone' do
      describe '#enabled' do
        subject(:enabled) { settings.appsec.standalone.enabled }

        context 'when DD_EXPERIMENTAL_APPSEC_STANDALONE_ENABLED' do
          around do |example|
            ClimateControl.modify('DD_EXPERIMENTAL_APPSEC_STANDALONE_ENABLED' => appsec_standalone_enabled) do
              example.run
            end
          end

          context 'is not defined' do
            let(:appsec_standalone_enabled) { nil }

            it { is_expected.to eq false }
          end

          context 'is defined' do
            let(:appsec_standalone_enabled) { 'true' }

            it { is_expected.to eq(true) }
          end
        end
      end

      describe '#enabled=' do
        subject(:set_appsec_standalone_enabled) { settings.appsec.standalone.enabled = appsec_standalone_enabled }

        [true, false].each do |value|
          context "when given #{value}" do
            let(:appsec_standalone_enabled) { value }

            before { set_appsec_standalone_enabled }

            it { expect(settings.appsec.standalone.enabled).to eq(value) }
          end
        end
      end
    end
  end
end
