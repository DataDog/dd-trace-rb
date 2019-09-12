require 'spec_helper'

require 'ddtrace'

RSpec.describe Datadog::Contrib::Configuration::Integration do
  subject(:integration) { described_class.new(definition, context) }

  let(:context) { double('configuration object') }
  let(:definition) do
    instance_double(
      Datadog::Contrib::Configuration::IntegrationDefinition,
      name: definition_name,
      default: definition_default,
      defer?: definition_defer?,
      enabled?: definition_enabled?
    )
  end

  let(:definition_name) { double('name') }
  let(:definition_default) { proc {} }
  let(:definition_defer?) { false }
  let(:definition_enabled?) { true }

  describe '#initialize' do
    it { expect(integration.definition).to be(definition) }
    it { expect(integration.callbacks).to eq([]) }
  end

  describe '#enable!' do
    subject(:enable!) { integration.enable! }

    context 'when enabled by default' do
      let(:definition_enabled?) { true }
      before { enable! }
      it { expect(integration.enabled?).to be(true) }
    end

    context 'when disabled by default' do
      let(:definition_enabled?) { false }
      it { expect { enable! }.to change { integration.enabled? }.from(false).to(true) }
    end
  end

  describe '#disable!' do
    subject(:disable!) { integration.disable! }

    context 'when enabled by default' do
      let(:definition_enabled?) { true }
      it { expect { disable! }.to change { integration.enabled? }.from(true).to(false) }
    end

    context 'when disabled by default' do
      let(:definition_enabled?) { false }
      before { disable! }
      it { expect(integration.enabled?).to be(false) }
    end
  end

  describe '#enabled?' do
    subject(:enabled?) { integration.enabled? }

    context 'when enabled by default' do
      let(:definition_enabled?) { true }
      it { is_expected.to be true }
    end

    context 'when disabled by default' do
      let(:definition_enabled?) { false }
      it { is_expected.to be false }
    end
  end

  describe '#defaults_applied?' do
    subject(:defaults_applied?) { integration.defaults_applied? }

    context 'before defaults are applied' do
      it { is_expected.to be false }
    end

    context 'when defaults are applied' do
      before { allow(Datadog.configuration).to receive(:set) }

      it do
        expect { integration.apply_defaults! }
          .to change { integration.defaults_applied? }
          .from(false)
          .to(true)
      end
    end
  end

  describe '#configure' do
    subject(:configure) { integration.configure(*args, &block) }
    let(:args) { [] }
    let(:block) { nil }

    before { allow(Datadog.configuration).to receive(:set) }

    context 'when given nothing' do
      before { expect(Datadog.configuration).to_not receive(:set) }
      it { expect { configure }.to_not(change { integration.enabled? }) }
      it { expect { configure }.to_not(change { integration.callbacks }) }
    end

    context 'when given false' do
      let(:args) { [false] }
      let(:definition_enabled?) { true }
      it { expect { configure }.to change { integration.enabled? }.from(true).to(false) }
    end

    context 'when given true' do
      let(:args) { [true] }
      let(:definition_enabled?) { false }
      it { expect { configure }.to change { integration.enabled? }.from(false).to(true) }
    end

    context 'when given a Hash' do
      let(:args) { [hash] }
      let(:hash) { { foo: :bar } }

      context 'and :defer is enabled by default' do
        let(:definition_defer?) { true }
        it { expect { configure }.to change { integration.callbacks }.from([]).to(array_including(kind_of(Proc))) }
      end

      context 'and :defer is disabled by default' do
        let(:definition_defer?) { false }

        context 'with defaults' do
          context 'that have not been applied' do
            before { configure }

            it 'applies the defaults before applying configuration' do
              expect(Datadog.configuration).to have_received(:set)
                .with(definition_name)
                .ordered
              expect(Datadog.configuration).to have_received(:set)
                .with(definition_name, hash)
                .ordered
            end
          end

          context 'that have already been applied' do
            before do
              integration.apply_defaults!
              configure
            end

            it 'applies the configuration without applying defaults twice' do
              expect(Datadog.configuration).to have_received(:set)
                .with(definition_name)
                .once
                .ordered
              expect(Datadog.configuration).to have_received(:set)
                .with(definition_name, hash)
                .ordered
            end
          end
        end
      end
    end

    context 'when given a block' do
      let(:block) { proc {} }

      context 'and :defer is enabled by default' do
        let(:definition_defer?) { true }
        it { expect { configure }.to change { integration.callbacks }.from([]).to(array_including(kind_of(Proc))) }
      end

      context 'and :defer is disabled by default' do
        let(:definition_defer?) { false }

        context 'with defaults' do
          let(:definition_default) { proc { defaults } }
          before { allow(context).to receive(:defaults) }

          context 'that have not been applied' do
            it 'applies the defaults before applying configuration' do
              expect(Datadog.configuration).to receive(:set) do |name, &b|
                @default_set ||= false

                expect(name).to be(definition_name)

                if @default_set
                  expect(b).to be(block)
                else
                  # Verify args
                  expect(b).to_not be(block)

                  # Verify default block behavior
                  b.call
                  expect(context).to have_received(:defaults)

                  @default_set = true
                end
              end

              configure
            end
          end

          context 'that have already been applied' do
            it 'applies the configuration without applying defaults twice' do
              integration.apply_defaults!

              expect(Datadog.configuration).to receive(:set) do |name, &b|
                expect(name).to be(definition_name)
                expect(b).to be(block)
              end

              configure
            end
          end
        end
      end
    end
  end

  describe '#add_callback' do
    subject(:add_callback) { integration.add_callback(*args, &block) }
    let(:args) { [{ foo: :bar }] }
    let(:block) { proc {} }

    it do
      expect { add_callback }
        .to change { integration.callbacks }
        .from([])
        .to(array_including(kind_of(Proc)))
    end

    describe 'adds a callback' do
      subject(:callback) { integration.callbacks.first }

      before { add_callback }

      it 'that sets configuration with the arguments provided when invoked' do
        expect(Datadog.configuration).to receive(:set) do |name, *a, &b|
          expect(name).to be(definition_name)
          expect(a).to eq(args)
          expect(b).to be(block)
        end

        callback.call
      end
    end
  end

  describe '#apply!' do
    subject(:apply!) { integration.apply!(*args, &block) }
    let(:args) { [{ foo: :bar }] }
    let(:block) { proc {} }

    it 'sets configuration with the arguments provided when invoked' do
      expect(Datadog.configuration).to receive(:set) do |name, *a, &b|
        expect(name).to be(definition_name)
        expect(a).to eq(args)
        expect(b).to be(block)
      end

      apply!
    end
  end

  describe '#apply_defaults!' do
    subject(:apply_defaults!) { integration.apply_defaults! }
    let(:definition_default) { proc { |*args| defaults(*args) } }

    before do
      allow(Datadog.configuration).to receive(:set)
      allow(context).to receive(:defaults)
    end

    it { expect { apply_defaults! }.to change { integration.defaults_applied? }.from(false).to(true) }
    it 'sets configuration with defaults' do
      expect(Datadog.configuration).to receive(:set) do |name, *_args, &block|
        # Verify args
        expect(name).to be(definition_name)
        expect(block).to be_a_kind_of(Proc)

        # Verify behavior default block
        block_args = [double('arg')]
        block.call(*block_args)
        expect(context).to have_received(:defaults)
          .with(*block_args)
      end

      apply_defaults!
    end
  end

  describe '#apply_callbacks!' do
    subject(:apply_callbacks!) { integration.apply_callbacks! }

    context 'when there are callbacks' do
      let(:first_callback_args) { { foo: :bar } }
      let(:second_callback_args) { { bar: :baz } }

      before do
        integration.add_callback(first_callback_args)
        integration.add_callback(second_callback_args)
        allow(Datadog.configuration).to receive(:set)
        apply_callbacks!
      end

      it 'invokes each callback in FIFO order' do
        expect(Datadog.configuration).to have_received(:set)
          .with(definition_name, first_callback_args)
          .ordered

        expect(Datadog.configuration).to have_received(:set)
          .with(definition_name, second_callback_args)
          .ordered
      end
    end
  end

  describe '#apply_and_activate!' do
    subject(:apply_and_activate!) { integration.apply_and_activate!(*args, &block) }
    let(:args) { [{ foo: :bar }] }
    let(:block) { proc {} }

    let(:definition_defer?) { true }
    let(:callback_args) { [{ bar: :baz }] }
    let(:callback_block) { proc {} }

    before do
      # Add a callback to test with
      integration.configure(*callback_args, &callback_block)
    end

    context 'when disabled' do
      before { integration.disable! }

      it do
        expect(Datadog.configuration).to_not receive(:use)
        expect(Datadog.configuration).to_not receive(:set)
        apply_and_activate!
      end
    end

    context 'when enabled' do
      before { integration.enable! }

      context 'and defaults' do
        let(:definition_default) { proc { defaults } }

        before do
          allow(Datadog.configuration).to receive(:use)
          allow(Datadog.configuration).to receive(:set)
          allow(context).to receive(:defaults)
        end

        context 'have already been applied' do
          before { integration.apply_defaults! }

          it do
            expect(Datadog.configuration).to receive(:set) do |name, *a, &b|
              @count ||= 0

              expect(name).to eq(definition_name)

              case @count
              when 0
                # First the callbacks
                expect(a).to eq(callback_args)
                expect(b).to be(callback_block)
              when 1
                # Then the overrides
                expect(a).to eq(args)
                expect(b).to be(block)
              else
                raise '#set called more than twice! Expected only twice'
              end

              @count += 1
            end.twice.ordered

            # Finally the activation
            expect(Datadog.configuration).to receive(:use)
              .with(definition_name)
              .ordered

            apply_and_activate!
          end
        end

        context 'have not been applied' do
          it do
            # First the defaults
            expect(Datadog.configuration).to receive(:set)
              .with(definition_name)
              .ordered

            # Then the callbacks
            expect(Datadog.configuration).to receive(:set)
              .with(definition_name, *callback_args)
              .ordered

            # Then the overrides
            expect(Datadog.configuration).to receive(:set)
              .with(definition_name, *args)
              .ordered

            # Finally the activation
            expect(Datadog.configuration).to receive(:use)
              .with(definition_name)
              .ordered

            apply_and_activate!
          end
        end
      end
    end
  end

  describe '#activate!' do
    subject(:activate!) { integration.activate! }

    before { allow(Datadog.configuration).to receive(:use) }

    context 'when enabled' do
      before { integration.enable! }

      it do
        activate!
        expect(Datadog.configuration).to have_received(:use)
          .with(definition_name)
      end
    end

    context 'when disabled' do
      before { integration.disable! }

      it do
        activate!
        expect(Datadog.configuration).to_not have_received(:use)
      end
    end
  end

  describe '#reset' do
    subject(:reset) { integration.reset }

    context 'after the integration has been configured and activated' do
      let(:definition_enabled?) { false }
      let(:definition_defer?) { true }

      before(:each) do
        allow(Datadog.configuration).to receive(:set)
        allow(Datadog.configuration).to receive(:use)

        # Apply state changes
        integration.configure(foo: :bar)
        integration.apply_and_activate!

        # Verify state has been set
        expect(integration.callbacks).to have(1).items
        expect(integration.defaults_applied?).to be true
        expect(integration.enabled?).to be true

        integration.reset
      end

      it 'resets values' do
        expect(integration.callbacks).to be_empty
        expect(integration.defaults_applied?).to be false
        expect(integration.enabled?).to be false
      end
    end
  end
end
