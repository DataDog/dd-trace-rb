require 'spec_helper'

require 'ddtrace'

RSpec.describe Datadog::Contrib::Configuration::Integrations do
  describe 'implemented' do
    subject(:integrations_class) do
      Class.new.tap do |klass|
        klass.send(:include, described_class)
      end
    end

    let(:integration_name) { :foo }

    shared_context 'registered integration' do
      let(:registered_integration) { instance_double(Datadog::Contrib::Integration) }

      before do
        allow(Datadog.registry).to receive(:[])
          .with(integration_name)
          .and_return(registered_integration)
      end
    end

    shared_context 'defined integration' do
      include_context 'registered integration'

      let(:integration_definition) { instance_double(Datadog::Contrib::Configuration::IntegrationDefinition) }
      let(:meta) { {} }
      let(:block) { proc {} }

      before do
        allow(Datadog::Contrib::Configuration::IntegrationDefinition).to receive(:new) do |name, m = {}, &b|
          expect(name).to eq(integration_name)
          expect(m).to eq(meta)
          expect(b).to be(block)

          integration_definition
        end

        integrations_class.send(:integration, integration_name, meta, &block)
      end
    end

    describe 'class behavior' do
      describe '#integrations' do
        subject(:integrations) { integrations_class.integrations }

        context 'for a class directly implementing Integrations' do
          it { is_expected.to be_a_kind_of(Datadog::Contrib::Configuration::IntegrationDefinitionSet) }
        end

        context 'on class inheriting from a class implementing Integrations' do
          let(:parent_class) do
            Class.new.tap do |klass|
              klass.send(:include, described_class)
            end
          end
          let(:integrations_class) { Class.new(parent_class) }

          context 'which defines some integrations' do
            include_context 'registered integration'

            before { parent_class.send(:integration, integration_name) }

            it { is_expected.to be_a_kind_of(Datadog::Contrib::Configuration::IntegrationDefinitionSet) }
            it { is_expected.to_not be(parent_class.integrations) }
            it { is_expected.to include(integration_name) }
          end
        end
      end

      describe '#integration' do
        subject(:integration) { integrations_class.send(:integration, integration_name, meta, &block) }

        let(:meta) { {} }
        let(:block) { proc {} }

        context 'when the integration is registered' do
          include_context 'registered integration'

          it 'creates an integration definition' do
            is_expected.to be_a_kind_of(Datadog::Contrib::Configuration::IntegrationDefinition)
            expect(integrations_class.integrations).to include(integration_name)
            expect(integrations_class.new).to respond_to(integration_name)
          end
        end
      end
    end

    describe 'instance behavior' do
      subject(:integrations_context) { integrations_class.new }

      shared_context 'configurable integration' do
        include_context 'defined integration'

        let(:integration) { instance_double(Datadog::Contrib::Configuration::Integration) }

        before do
          allow(Datadog::Contrib::Configuration::Integration).to receive(:new)
            .with(integration_definition, integrations_context)
            .and_return(integration)
        end
      end

      describe '#integrations' do
        subject(:integrations) { integrations_context.integrations }
        it { is_expected.to be_a_kind_of(Datadog::Contrib::Configuration::IntegrationSet) }
      end

      describe '#apply_and_activate!' do
        subject(:apply_and_activate!) { integrations_context.apply_and_activate!(integration_name, *args, &block) }
        let(:args) { [{ bar: :baz }] }
        let(:block) { proc {} }

        context 'when the integration is defined' do
          include_context 'configurable integration'

          it 'applies and activates the integration' do
            expect(integration).to receive(:apply_and_activate!) do |*a, &b|
              expect(a).to eq(args)
              expect(b).to be(block)
            end

            apply_and_activate!
          end
        end

        context 'when the integration is not defined' do
          it { expect { apply_and_activate! }.to raise_error(described_class::InvalidIntegrationError) }
        end
      end

      describe '#configure_integration' do
        subject(:configure_integration) { integrations_context.configure_integration(integration_name, *args, &block) }
        let(:args) { [{ bar: :baz }] }
        let(:block) { proc {} }

        context 'when the integration is defined' do
          include_context 'configurable integration'

          it 'configures the integration' do
            expect(integration).to receive(:configure) do |*a, &b|
              expect(a).to eq(args)
              expect(b).to be(block)
            end

            configure_integration
          end
        end

        context 'when the integration is not defined' do
          it { expect { configure_integration }.to raise_error(described_class::InvalidIntegrationError) }
        end
      end

      describe '#get_integration' do
        subject(:get_integration) { integrations_context.get_integration(integration_name) }

        context 'when the integration is defined' do
          include_context 'configurable integration'

          it { is_expected.to be(integration) }
        end

        context 'when the integration is not defined' do
          it { expect { get_integration }.to raise_error(described_class::InvalidIntegrationError) }
        end
      end

      describe '#integrations_hash' do
        subject(:integrations_hash) { integrations_context.integrations_hash }

        context 'when no integrations are defined' do
          it { is_expected.to eq({}) }
        end

        context 'when integrations are configured' do
          include_context 'configurable integration'
          before { integrations_context.get_integration(integration_name) }
          it { is_expected.to eq(foo: integration) }
        end
      end

      describe '#reset_integrations!' do
        subject(:reset_integrations!) { integrations_context.reset_integrations! }

        context 'when an integration is configured' do
          include_context 'configurable integration'

          before { integrations_context.get_integration(integration_name) }

          it 'resets the integration to its default value' do
            expect(integration).to receive(:reset)
            reset_integrations!
          end
        end
      end
    end
  end
end
