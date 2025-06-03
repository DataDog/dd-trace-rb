require 'datadog/appsec/spec_helper'
require 'datadog/appsec/component'

RSpec.describe Datadog::AppSec::Component do
  let(:telemetry) { instance_double(Datadog::Core::Telemetry::Component) }
  let(:settings) do
    settings = Datadog::Core::Configuration::Settings.new
    settings.appsec.enabled = appsec_enabled
    settings
  end
  let(:appsec_enabled) { true }

  describe '.build_appsec_component' do
    context 'when appsec is enabled' do
      let(:appsec_enabled) { true }

      it 'returns a Datadog::AppSec::Component instance' do
        component = described_class.build_appsec_component(settings, telemetry: telemetry)
        expect(component).to be_a(described_class)
      end

      context 'when using ffi version that is known to leak memory with Ruby >= 3.3.0' do
        before do
          stub_const('RUBY_VERSION', '3.3.0')
          allow(Gem).to receive(:loaded_specs).and_return('ffi' => double(version: Gem::Version.new('1.15.4')))
        end

        it 'returns nil, warns and reports telemetry' do
          expect(Datadog.logger).to receive(:warn)
          expect(telemetry).to receive(:error)
            .with('AppSec: Component not loaded, ffi version is leaky with ruby > 3.3.0')

          component = described_class.build_appsec_component(settings, telemetry: telemetry)
          expect(component).to be_nil
        end
      end

      context 'when ffi is not loaded' do
        before { allow(Gem).to receive(:loaded_specs).and_return({}) }

        it 'returns nil, warns and reports telemetry' do
          expect(Datadog.logger).to receive(:warn)
          expect(telemetry).to receive(:error).with('AppSec: Component not loaded, due to missing FFI gem')

          component = described_class.build_appsec_component(settings, telemetry: telemetry)
          expect(component).to be_nil
        end
      end

      it 'returns nil when security engine fails to instantiate' do
        settings.appsec.ruleset = {}

        expect(telemetry).to receive(:report)
        expect(Datadog.logger).to receive(:warn)

        expect(described_class.build_appsec_component(settings, telemetry: telemetry)).to be_nil
      end
    end

    context 'when appsec is not enabled' do
      let(:appsec_enabled) { false }

      it 'returns nil' do
        component = described_class.build_appsec_component(settings, telemetry: telemetry)
        expect(component).to be_nil
      end
    end

    context 'when appsec is not active' do
      it 'returns nil' do
        component = described_class.build_appsec_component(
          double(Datadog::Core::Configuration::Settings),
          telemetry: telemetry
        )
        expect(component).to be_nil
      end
    end
  end

  describe '#reconfigure!' do
    before { allow(telemetry).to receive(:report) }

    let(:telemetry) { instance_double(Datadog::Core::Telemetry::Component) }
    let(:ruleset) do
      {
        'exclusions' => [{
          'conditions' => [{
            'operator' => 'ip_match',
            'parameters' => {
              'inputs' => [{
                'address' => 'http.client_ip'
              }]
            }
          }]
        }],
        'metadata' => {
          'rules_version' => '1.5.2'
        },
        'rules' => [{
          'conditions' => [{
            'operator' => 'ip_match',
            'parameters' => {
              'data' => 'blocked_ips',
              'inputs' => [{
                'address' => 'http.client_ip'
              }]
            }
          }],
          'id' => 'blk-001-001',
          'name' => 'Block IP Addresses',
          'on_match' => ['block'],
          'tags' => {
            'category' => 'security_response', 'type' => 'block_ip'
          },
          'transformers' => []
        }],
        'rules_data' => [{
          'data' => [{
            'expiration' => 1678972458,
            'value' => '42.42.42.1'
          }]
        }],
        'version' => '2.2'
      }
    end

    context 'lock' do
      it 'makes sure to synchronize' do
        mutex = Mutex.new
        component = described_class.build_appsec_component(settings, telemetry: telemetry)
        component.instance_variable_set(:@mutex, mutex)
        expect(mutex).to receive(:synchronize)
        component.reconfigure!
      end
    end
  end

  describe '#reconfigure_lock' do
    context 'lock' do
      it 'makes sure to synchronize' do
        mutex = Mutex.new
        component = described_class.build_appsec_component(settings, telemetry: telemetry)
        component.instance_variable_set(:@mutex, mutex)
        expect(mutex).to receive(:synchronize)
        component.reconfigure_lock(&proc {})
      end
    end
  end

  describe '#shutdown!' do
    context 'lock' do
      it 'makes sure to synchronize' do
        mutex = Mutex.new
        component = described_class.build_appsec_component(settings, telemetry: telemetry)
        component.instance_variable_set(:@mutex, mutex)
        expect(mutex).to receive(:synchronize)
        component.shutdown!
      end
    end
  end
end
