require 'datadog/tracing/contrib/support/spec_helper'

require 'datadog/tracing/contrib'

RSpec.describe Datadog::Tracing::Contrib::Extensions do
  shared_context 'registry with integration' do
    let(:registry) { Datadog::Tracing::Contrib::Registry.new }
    let(:integration_name) { :example }
    let(:integration) { registry[integration_name] }

    let(:integration_class) do
      available = self.available
      compatible = self.compatible
      loaded = self.loaded
      gems = self.gems
      patcher = self.patcher
      Class.new do
        include Datadog::Tracing::Contrib::Integration
        include Datadog::Tracing::Contrib::Configurable

        define_singleton_method(:available?) { available }
        define_singleton_method(:compatible?) { compatible }
        define_singleton_method(:loaded?) { loaded }
        define_singleton_method(:gems) { gems }

        define_method(:patcher) { patcher }
      end
    end

    let(:available) { true }
    let(:compatible) { true }
    let(:loaded) { true }
    let(:gems) { ['test gem 1', 'test gem 2'] } # Invalid gem names, for testing purposes

    let(:patcher) do
      Class.new do
        include Datadog::Tracing::Contrib::Patcher
        def patch
          nil
        end
      end.new
    end

    let(:configurable_module) do
      stub_const(
        'Configurable',
        Module.new do
          include Datadog::Tracing::Contrib::Configurable
        end
      )
    end

    before do
      integration_name = self.integration_name
      registry = self.registry
      integration_class.class_eval do
        register_as integration_name, registry: registry
      end
    end

    after do
      patcher.send(:patch_only_once).send(:reset_ran_once_state_for_tests)
    end
  end

  context 'for' do
    describe 'Datadog.configure' do
      subject(:configure) { Datadog.configure(&block) }

      context 'calling c.tracing.instrument for an integration' do
        include_context 'registry with integration' do
          before { stub_const('Datadog::Tracing::Contrib::REGISTRY', registry) }
        end

        let(:block) { proc { |c| c.tracing.instrument integration_name } }

        shared_examples 'registers require monitor' do
          it 'configures & patches the integration' do
            expect(integration).to receive(:configure).with(:default, any_args)
            expect(integration).to receive(:patch).and_call_original

            configure

            expect(integration.patcher.patch_successful).to be_falsey
          end

          it 'register require monitor' do
            allow(integration).to receive(:patch).and_call_original

            expect(Datadog::Tracing::Contrib::Kernel).to receive(:patch!)

            expect(Datadog::Tracing::Contrib::Kernel).to receive(:on_require).with('test gem 1') do |&block|
              # Because we are forcing the block to be called to make assertions,
              # the patcher will raise a warning because the gem is not loaded, which is what we expect.
              expect(Datadog.logger).to receive(:warn).once

              expect(integration).to have_received(:patch).once
              block.call
              expect(integration).to have_received(:patch).twice
            end

            expect(Datadog::Tracing::Contrib::Kernel).to receive(:on_require).with('test gem 2') do |&block|
              # Because we are forcing the block to be called to make assertions,
              # the patcher will raise a warning because the gem is not loaded, which is what we expect.
              expect(Datadog.logger).to receive(:warn).once

              expect(integration).to have_received(:patch).twice
              block.call
              expect(integration).to have_received(:patch).thrice
            end
            configure
          end

          it 'sends a telemetry integrations change event' do
            expect_any_instance_of(Datadog::Core::Telemetry::Client).to receive(:integrations_change!)
            configure
          end
        end

        shared_examples 'patches immediately' do
          it 'configures & patches the integration' do
            expect(integration).to receive(:configure).with(:default, any_args)
            expect(integration).to receive(:patch).and_call_original

            configure

            expect(integration.patcher.patch_successful).to be_truthy
          end

          it 'does not register require monitor' do
            expect(Datadog::Tracing::Contrib::Kernel).to_not receive(:patch!)
            expect(Datadog::Tracing::Contrib::Kernel).to_not receive(:on_require)
            configure
          end

          it 'sends a telemetry integrations change event' do
            expect_any_instance_of(Datadog::Core::Telemetry::Client).to receive(:integrations_change!)
            configure
          end
        end

        shared_examples 'cannot instrument' do
          it 'configures & patches the integration' do
            expect(integration).to receive(:configure).with(:default, any_args)
            expect(integration).to receive(:patch).and_call_original

            configure

            expect(integration.patcher.patch_successful).to be_falsey
          end

          it 'does not register require monitor' do
            expect(Datadog::Tracing::Contrib::Kernel).to_not receive(:patch!)
            expect(Datadog::Tracing::Contrib::Kernel).to_not receive(:on_require)
            configure
          end

          it 'sends a telemetry integrations change event' do
            expect_any_instance_of(Datadog::Core::Telemetry::Client).to receive(:integrations_change!)
            configure
          end
        end

        context 'that is available' do
          let(:available) { true }

          context 'and compatible' do
            let(:compatible) { true }

            context 'and loaded' do
              let(:loaded) { true }
              it_behaves_like 'patches immediately'
            end

            context 'and not loaded' do
              let(:loaded) { false }
              it_behaves_like 'registers require monitor'

              context 'but is loaded while we are registering the monitors' do
                it 'register require monitor and also patches' do
                  expect(Datadog::Tracing::Contrib::Kernel).to receive(:patch!) do
                    # Load the gems!
                    allow(integration.class).to receive(:loaded?).and_return(true)
                  end

                  expect(Datadog::Tracing::Contrib::Kernel).to receive(:on_require).twice

                  expect(integration).to receive(:configure).with(:default, any_args)
                  expect(integration).to receive(:patch).and_call_original.twice

                  configure

                  expect(integration.patcher.patch_successful).to be_truthy
                end

                it 'sends a telemetry integrations change event' do
                  expect_any_instance_of(Datadog::Core::Telemetry::Client).to receive(:integrations_change!)
                  configure
                end
              end
            end
          end

          context 'and not compatible' do
            let(:compatible) { false }
            it_behaves_like 'cannot instrument'
          end
        end

        context 'that is not available' do
          let(:available) { false }
          it_behaves_like 'cannot instrument'
        end
      end
    end

    describe Datadog::Core::Configuration::Settings do
      include_context 'registry with integration'

      subject(:settings) { described_class.new }

      before { stub_const('Datadog::Tracing::Contrib::REGISTRY', registry) }

      describe '.tracing' do
        subject(:settings) { described_class.new.tracing }

        describe '#settings' do
          describe '#peer_service_mapping' do
            subject { settings.contrib.peer_service_mapping }

            context 'when given environment variable DD_TRACE_PEER_SERVICE_MAPPING' do
              around do |example|
                ClimateControl.modify(
                  'DD_TRACE_PEER_SERVICE_MAPPING' => env_var
                ) do
                  example.run
                end
              end

              context 'is not defined' do
                let(:env_var) { nil }

                it { is_expected.to eq({}) }
              end

              context 'is defined' do
                let(:env_var) { 'key:value' }

                it { is_expected.to eq({ 'key' => 'value' }) }
              end
            end
          end

          describe '#global_default_service_name_enabled' do
            subject { settings.contrib.global_default_service_name.enabled }

            context 'when given environment variable DD_TRACE_REMOVE_INTEGRATION_SERVICE_NAMES_ENABLED' do
              around do |example|
                ClimateControl.modify(
                  'DD_TRACE_REMOVE_INTEGRATION_SERVICE_NAMES_ENABLED' => env_var
                ) do
                  example.run
                end
              end

              context 'is not defined' do
                let(:env_var) { nil }

                it { is_expected.to be false }
              end

              context 'is defined' do
                let(:env_var) { 'true' }

                it { is_expected.to be true }
              end
            end
          end
        end

        describe '#[]' do
          subject(:get) { settings[integration_name] }
          let(:default_settings) { integration.default_configuration }

          context 'when the integration doesn\'t exist' do
            it do
              expect { settings[:foobar] }.to raise_error(
                Datadog::Tracing::Contrib::Extensions::Configuration::Settings::InvalidIntegrationError
              )
            end
          end

          context 'when integration exists' do
            include_context 'registry with integration'

            context 'and is instrumented' do
              let(:instrument_options) { {} }

              before { settings.send(:instrument, integration_name, instrument_options) }

              context 'with a matching described configuration' do
                let(:matcher) { double('matcher') }
                let(:instrument_options) { { describes: matcher } }

                context 'using the same matcher' do
                  subject(:get) { settings[integration_name, matcher] }

                  it 'retrieves the described configuration' do
                    is_expected.to_not be(default_settings)
                    is_expected.to be_a(Datadog::Tracing::Contrib::Configuration::Settings)
                  end
                end

                context 'using a different matcher' do
                  subject(:get) { settings[integration_name, other_matcher] }
                  let(:other_matcher) { double('other matcher') }

                  it 'retrieves the default configuration' do
                    is_expected.to be(default_settings)
                  end
                end
              end

              context 'with no matching described configuration' do
                it 'retrieves the default configuration' do
                  is_expected.to be(default_settings)
                end
              end
            end
          end
        end

        describe '#instrument' do
          subject(:result) { settings.send(:instrument, integration_name, options) }

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

          context 'for an integration that includes Datadog::Tracing::Contrib::Integration' do
            include_context 'registry with integration' do
              let(:integration) { registry[integration_name] }

              let(:integration_class) do
                patcher_module

                Class.new do
                  include Datadog::Tracing::Contrib::Integration
                  include Datadog::Tracing::Contrib::Configurable

                  def self.version
                    Gem::Version.new('0.1')
                  end

                  def patcher
                    Patcher
                  end
                end
              end

              let(:patcher_module) do
                stub_const(
                  'Patcher',
                  Module.new do
                    include Datadog::Tracing::Contrib::Patcher

                    def self.patch
                      true
                    end
                  end
                )
              end
            end

            context 'which is provided only a name' do
              it do
                expect(integration).to receive(:configure).with(:default, {})
                settings.send(:instrument, integration_name)
              end
            end

            context 'which is provided a block' do
              it do
                expect(integration).to receive(:configure).with(:default, {}).and_call_original
                expect { |b| settings.send(:instrument, integration_name, options, &b) }.to yield_with_args(
                  a_kind_of(Datadog::Tracing::Contrib::Configuration::Settings)
                )
              end
            end
          end
        end
      end
    end
  end
end
