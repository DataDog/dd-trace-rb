require 'spec_helper'

require 'ddtrace'

RSpec.describe Datadog::Core::Configuration::Base do
  describe 'implemented' do
    subject(:base_class) do
      Class.new.tap do |klass|
        klass.include(described_class)
      end
    end

    describe 'class behavior' do
      describe '#settings' do
        subject(:settings) { base_class.send(:settings, name, &block) }

        context 'given a name and block' do
          let(:name) { :debug }
          let(:block) { proc { option :enabled } }

          describe 'defines a settings option' do
            subject(:definition) { base_class.options[name] }

            before { settings }

            it { is_expected.to be_a_kind_of(Datadog::Core::Configuration::OptionDefinition) }

            it 'sets default properties' do
              expect(definition.type).to be_a_kind_of(Class)
              expect(definition.type.ancestors).to include(described_class)

              is_expected.to have_attributes(
                default: kind_of(Proc),
                lazy: true,
                resetter: kind_of(Proc)
              )
            end

            describe 'when instantiated' do
              subject(:option) { Datadog::Core::Configuration::Option.new(definition, self) }
              let(:settings_object) { option.default_value }

              it { expect(settings_object).to be_a_kind_of(described_class) }
              it { expect(settings_object.option_defined?(:enabled)).to be true }
            end
          end
        end
      end
    end

    describe 'instance behavior' do
      subject(:base_object) { base_class.new }

      it { is_expected.to be_a_kind_of(Datadog::Core::Environment::VariableHelpers) }

      describe '#initialize' do
        subject(:base_object) { base_class.new(options) }

        let(:options) { { foo: :bar } }

        before { allow_any_instance_of(base_class).to receive(:configure) }

        it do
          is_expected.to be_a_kind_of(base_class)
          expect(base_object).to have_received(:configure).with(options)
        end
      end

      describe '#configure' do
        subject(:configure) { base_object.configure(options) }

        context 'when given an option' do
          let(:options) { { foo: :bar } }

          context 'that is not defined' do
            it { expect { configure }.to_not raise_error }
          end

          context 'which matches a method on the class' do
            before do
              base_class.send(:define_method, :foo=) { |_value| }
              allow(base_object).to receive(:foo=)
            end

            it 'invokes the method with the value' do
              configure
              expect(base_object).to have_received(:foo=)
                .with(:bar)
            end
          end

          context 'which has been defined on the class' do
            before { base_class.send(:option, :foo) }

            it 'invokes the method with the value' do
              configure
              expect(base_object.foo).to eq(:bar)
            end
          end
        end
      end

      describe '#to_h' do
        subject(:hash) { base_object.to_h }

        let(:options_hash) { double('options hash') }

        before do
          allow(base_object).to receive(:options_hash)
            .and_return(options_hash)
        end

        it do
          is_expected.to be(options_hash)
          expect(base_object).to have_received(:options_hash)
        end
      end

      describe '#dig' do
        subject(:dig) { base_object.dig(*options) }
        let(:options) { 'debug' }

        let(:settings) { base_class.send(:settings, name, &block) }
        let(:name) { :debug }
        let(:block) { proc { option :enabled, default: true } }
        let(:definition) { base_class.options[name] }

        before do
          settings
          definition
        end

        context 'when given one arg' do
          let(:options) { 'debug' }
          it { is_expected.to be_a_kind_of(Datadog::Core::Configuration::Options) }
        end

        context 'when given more than one arg' do
          let(:options) { %w[debug enabled] }

          it { is_expected.to be(true) }
        end
      end

      describe '#reset!' do
        subject(:reset!) { base_object.reset! }

        before do
          allow(base_object).to receive(:reset_options!)
          reset!
        end

        it 'resets the options' do
          expect(base_object).to have_received(:reset_options!)
        end
      end
    end
  end
end
