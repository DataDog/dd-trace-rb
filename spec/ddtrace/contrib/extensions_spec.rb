require 'spec_helper'

require 'ddtrace'
require 'ddtrace/contrib/extensions'

RSpec.describe Datadog::Contrib::Extensions do
  context 'for' do
    describe Datadog::Configuration::Settings do
      subject(:settings) { described_class.new(registry: registry) }
      let(:registry) { Datadog::Contrib::Registry.new }

      describe '#[]' do
        context 'when the integration doesn\'t exist' do
          it do
            expect { settings[:foobar] }.to raise_error(
              Datadog::Contrib::Extensions::Configuration::Settings::InvalidIntegrationError
            )
          end
        end
      end

      describe '#use' do
        subject(:result) { settings.use(name, options) }
        let(:name) { :example }
        let(:integration) { double('integration') }
        let(:options) { {} }

        before(:each) do
          registry.add(name, integration)
        end

        context 'for a generic integration' do
          before(:each) do
            expect(integration).to receive(:configure).with(:default, options).and_return([])
            expect(integration).to receive(:patch).and_return(true)
          end

          it { expect { result }.to_not raise_error }
        end

        context 'for an integration that includes Datadog::Contrib::Integration' do
          let(:patcher_module) do
            stub_const('Patcher', Module.new do
              include Datadog::Contrib::Patcher

              def self.patch
                true
              end
            end)
          end

          let(:integration_class) do
            patcher_module

            Class.new do
              include Datadog::Contrib::Integration

              def self.version
                Gem::Version.new('0.1')
              end

              def patcher
                Patcher
              end
            end
          end

          let(:integration) do
            integration_class.new(name)
          end

          context 'which is provided only a name' do
            it do
              expect(integration).to receive(:configure).with(:default, {})
              settings.use(name)
            end
          end

          context 'which is provided a block' do
            it do
              expect(integration).to receive(:configure).with(:default, {}).and_call_original
              expect { |b| settings.use(name, options, &b) }.to yield_with_args(
                a_kind_of(Datadog::Contrib::Configuration::Settings)
              )
            end
          end
        end
      end
    end
  end
end
