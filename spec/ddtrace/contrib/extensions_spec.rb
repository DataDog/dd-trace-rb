require 'ddtrace/contrib/support/spec_helper'

require 'ddtrace'
require 'ddtrace/contrib/extensions'

RSpec.describe Datadog::Contrib::Extensions do
  shared_context 'registry with integration' do
    let(:registry) { Datadog::Contrib::Registry.new }
    let(:integration_name) { :example }
    let(:integration) { integration_class.new(integration_name) }
    let(:integration_class) do
      Class.new do
        include Datadog::Contrib::Integration
        include Datadog::Contrib::Configurable
      end
    end

    let(:configurable_module) do
      stub_const('Configurable', Module.new do
        include Datadog::Contrib::Configurable
      end)
    end

    before { registry.add(integration_name, integration) }
  end

  context 'for' do
    describe Datadog do
      describe '#configure' do
        include_context 'registry with integration' do
          before do
            allow(described_class.configuration).to receive(:registry).and_return(registry)
          end
        end

        context 'given a block' do
          subject(:configure) { described_class.configure(&block) }

          context 'that calls #use for an integration' do
            let(:block) { proc { |c| c.use integration_name } }

            it 'configures & patches the integration' do
              expect(integration).to receive(:configure).with(:default, any_args)
              expect(integration).to receive(:patch).and_call_original
              configure
            end
          end

          context 'that calls #instrument for an integration' do
            let(:block) { proc { |c| c.instrument integration_name } }

            it 'configures & patches the integration' do
              expect(integration).to receive(:configure).with(:default, any_args)
              expect(integration).to receive(:patch).and_call_original
              configure
            end
          end
        end

        context 'given a target and options' do
          subject(:configure) { described_class.configure(target, opts) }

          let(:target) { double('target') }
          let(:opts) { {} }

          it { expect { configure }.to_not raise_error }
        end
      end
    end

    describe Datadog::Configuration::Settings do
      include_context 'registry with integration'

      subject(:settings) { described_class.new(registry: registry) }

      describe '#[]' do
        context 'when the integration doesn\'t exist' do
          it do
            expect { settings[:foobar] }.to raise_error(
              Datadog::Contrib::Extensions::Configuration::Settings::InvalidIntegrationError
            )
          end
        end
      end

      describe '#configuration' do
        include_context 'registry with integration'

        subject(:configuration) { settings.configuration(integration_name, matcher) }

        let(:matcher) { double('matcher') }
        let(:options) { {} }
        let(:default_settings) { settings.configuration(integration_name) }

        before { settings.use(integration_name, options) }

        context 'with a matching described configuration' do
          let(:options) { { describes: matcher } }

          it 'retrieves the described configuration' do
            is_expected.to_not eq(default_settings)
            is_expected.to be_a(Datadog::Contrib::Configuration::Settings)
          end
        end

        context 'with no matching described configuration' do
          it 'retrieves the default configuration' do
            is_expected.to eq(default_settings)
          end
        end
      end

      describe '#use' do
        subject(:result) { settings.use(integration_name, options) }

        let(:options) { {} }

        context 'for a generic integration' do
          include_context 'registry with integration'

          before do
            expect(integration).to receive(:configure).with(:default, options).and_return([])
            expect(integration).to_not receive(:patch)
          end

          it do
            expect { result }.to_not raise_error
            expect(settings.integrations_pending_activation).to include(integration)
            expect(settings.instrumented_integrations).to include(integration_name => integration)
          end
        end

        context 'for an integration that includes Datadog::Contrib::Integration' do
          include_context 'registry with integration' do
            let(:integration) do
              integration_class.new(integration_name)
            end

            let(:integration_class) do
              patcher_module

              Class.new do
                include Datadog::Contrib::Integration
                include Datadog::Contrib::Configurable

                def self.version
                  Gem::Version.new('0.1')
                end

                def patcher
                  Patcher
                end
              end
            end

            let(:patcher_module) do
              stub_const('Patcher', Module.new do
                include Datadog::Contrib::Patcher

                def self.patch
                  true
                end
              end)
            end
          end

          context 'which is provided only a name' do
            it do
              expect(integration).to receive(:configure).with(:default, {})
              settings.use(integration_name)
            end
          end

          context 'which is provided a block' do
            it do
              expect(integration).to receive(:configure).with(:default, {}).and_call_original
              expect { |b| settings.use(integration_name, options, &b) }.to yield_with_args(
                a_kind_of(Datadog::Contrib::Configuration::Settings)
              )
            end
          end
        end
      end
    end
  end
end
