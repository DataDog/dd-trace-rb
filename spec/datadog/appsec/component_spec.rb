require 'datadog/appsec/spec_helper'
require 'datadog/appsec/component'

RSpec.describe Datadog::AppSec::Component do
  describe '.build_appsec_component' do
    let(:settings) do
      settings = Datadog::Core::Configuration::Settings.new
      settings.appsec.enabled = appsec_enabled
      settings
    end

    let(:telemetry) { instance_double(Datadog::Core::Telemetry::Component) }

    context 'when appsec is enabled' do
      let(:appsec_enabled) { true }

      it 'returns a Datadog::AppSec::Component instance' do
        component = described_class.build_appsec_component(settings, telemetry: telemetry)
        expect(component).to be_a(described_class)
      end

      context 'when processor is ready' do
        it 'returns a Datadog::AppSec::Component with a processor instance' do
          expect_any_instance_of(Datadog::AppSec::Processor).to receive(:ready?).and_return(true)
          component = described_class.build_appsec_component(settings, telemetry: telemetry)

          expect(component.processor).to be_a(Datadog::AppSec::Processor)
        end
      end

      context 'when processor fail to instanciate' do
        it 'returns a Datadog::AppSec::Component with a nil processor' do
          expect_any_instance_of(Datadog::AppSec::Processor).to receive(:ready?).and_return(false)
          component = described_class.build_appsec_component(settings, telemetry: telemetry)

          expect(component.processor).to be_nil
        end
      end

      context 'when loading ruleset from settings fails' do
        it 'returns a Datadog::AppSec::Component with a nil processor' do
          expect(Datadog::AppSec::Processor::RuleLoader).to receive(:load_rules).and_return(nil)

          component = described_class.build_appsec_component(settings, telemetry: telemetry)

          expect(component.processor).to be_nil
        end
      end

      context 'when static rules have actions defined' do
        it 'calls Datadog::AppSec::Processor::Actions.merge' do
          actions = [
            {
              'id' => 'block',
              'type' => 'block_request',
              'parameters' => {
                'type' => 'auto',
                'status_code' => 403,

              }
            }
          ]
          ruleset =
            {
              'version' => '2.2',
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
              'actions' => actions
            }

          expect(Datadog::AppSec::Processor::Actions).to receive(:merge).with(actions)
          expect(Datadog::AppSec::Processor::RuleLoader).to receive(:load_rules).and_return(ruleset)

          component = described_class.build_appsec_component(settings, telemetry: telemetry)

          expect(component.processor).to be_a(Datadog::AppSec::Processor)
        end
      end

      context 'when static rules do not  have actions defined' do
        it 'calls Datadog::AppSec::Processor::Actions.merge' do
          ruleset =
            {
              'version' => '2.2',
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
            }

          expect(Datadog::AppSec::Processor::Actions).to_not receive(:merge)
          expect(Datadog::AppSec::Processor::RuleLoader).to receive(:load_rules).and_return(ruleset)

          component = described_class.build_appsec_component(settings, telemetry: telemetry)

          expect(component.processor).to be_a(Datadog::AppSec::Processor)
        end
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

  describe '#reconfigure' do
    let(:telemetry) { instance_double(Datadog::Core::Telemetry::Component, report: nil) }
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

    let(:actions) { [] }

    context 'lock' do
      it 'makes sure to synchronize' do
        mutex = Mutex.new
        processor = instance_double(Datadog::AppSec::Processor)
        component = described_class.new(processor: processor)
        component.instance_variable_set(:@mutex, mutex)
        expect(mutex).to receive(:synchronize)
        component.reconfigure(ruleset: {}, actions: actions, telemetry: telemetry)
      end
    end

    context 'actions' do
      it 'merges the actions' do
        processor = instance_double(Datadog::AppSec::Processor)
        expect(processor).to receive(:finalize)
        component = described_class.new(processor: processor)

        expect(Datadog::AppSec::Processor::Actions).to receive(:merge).with(actions)
        component.reconfigure(ruleset: ruleset, actions: actions, telemetry: telemetry)
      end
    end

    context 'when the new processor is ready' do
      it 'swaps the processor instance and finalize the old processor' do
        processor = instance_double(Datadog::AppSec::Processor)
        component = described_class.new(processor: processor)

        old_processor = component.processor

        expect(old_processor).to receive(:finalize)
        component.reconfigure(ruleset: ruleset, actions: actions, telemetry: telemetry)
        new_processor = component.processor
        expect(new_processor).to_not eq(old_processor)
        new_processor.finalize
      end
    end

    context 'when the new processor is ready, and old processor is nil' do
      it 'swaps the processor instance and do not finalize the old processor' do
        processor = nil
        component = described_class.new(processor: processor)

        old_processor = component.processor

        expect(old_processor).to_not receive(:finalize)
        component.reconfigure(ruleset: ruleset, actions: actions, telemetry: telemetry)
        new_processor = component.processor
        expect(new_processor).to_not eq(old_processor)
        new_processor.finalize
      end
    end

    context 'when the new processor is not ready' do
      it 'does not swap the processor instance and finalize the old processor' do
        processor = instance_double(Datadog::AppSec::Processor)
        component = described_class.new(processor: processor)

        old_processor = component.processor

        ruleset = { 'invalid_one' => true }

        expect(old_processor).to_not receive(:finalize)
        component.reconfigure(ruleset: ruleset, actions: actions, telemetry: telemetry)
        expect(component.processor).to eq(old_processor)
      end
    end
  end

  describe '#reconfigure_lock' do
    context 'lock' do
      it 'makes sure to synchronize' do
        mutex = Mutex.new
        processor = instance_double(Datadog::AppSec::Processor)
        component = described_class.new(processor: processor)
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
        processor = instance_double(Datadog::AppSec::Processor)
        component = described_class.new(processor: processor)
        component.instance_variable_set(:@mutex, mutex)
        expect(mutex).to receive(:synchronize)
        component.shutdown!
      end
    end

    context 'when processor is not nil and ready' do
      it 'finalizes the processor' do
        processor = instance_double(Datadog::AppSec::Processor)

        component = described_class.new(processor: processor)
        expect(processor).to receive(:ready?).and_return(true)
        expect(processor).to receive(:finalize)
        component.shutdown!
      end
    end

    context 'when processor is not ready' do
      it 'does not finalize the processor' do
        processor = instance_double(Datadog::AppSec::Processor)
        expect(processor).to receive(:ready?).and_return(false)

        component = described_class.new(processor: processor)

        expect(processor).to_not receive(:finalize)
        component.shutdown!
      end
    end

    context 'when processor is nil' do
      it 'does not finalize the processor' do
        component = described_class.new(processor: nil)

        expect_any_instance_of(Datadog::AppSec::Processor).to_not receive(:finalize)
        component.shutdown!
      end
    end
  end
end
