require 'spec_helper'

require 'ddtrace'

RSpec.describe Datadog::Core::Configuration::Options do
  describe 'implemented' do
    subject(:options_class) do
      Class.new.tap do |klass|
        klass.include(described_class)
      end
    end

    describe 'class behavior' do
      describe '#options' do
        subject(:options) { options_class.options }

        context 'for a class directly implementing Options' do
          it { is_expected.to be_a_kind_of(Datadog::Core::Configuration::OptionDefinitionSet) }
        end

        context 'on class inheriting from a class implementing Options' do
          let(:parent_class) do
            Class.new.tap do |klass|
              klass.include(described_class)
            end
          end
          let(:options_class) { Class.new(parent_class) }

          context 'which defines some options' do
            before { parent_class.send(:option, :foo) }

            it { is_expected.to be_a_kind_of(Datadog::Core::Configuration::OptionDefinitionSet) }
            it { is_expected.to_not be(parent_class.options) }
            it { is_expected.to include(:foo) }
          end
        end
      end

      describe '#option' do
        subject(:option) { options_class.send(:option, name, meta, &block) }

        let(:name) { :foo }
        let(:meta) { {} }
        let(:block) { proc {} }

        it 'creates an option definition' do
          is_expected.to be_a_kind_of(Datadog::Core::Configuration::OptionDefinition)
          expect(options_class.options).to include(name)
          expect(options_class.new).to respond_to(name)
          expect(options_class.new).to respond_to("#{name}=")
        end

        context 'when given a block' do
          it 'invokes it with a builder' do
            expect { |b| options_class.send(:option, name, meta, &b) }.to yield_with_args(
              kind_of(Datadog::Core::Configuration::OptionDefinition::Builder)
            )
          end

          context 'that defines helpers' do
            context 'to disable defaults' do
              let(:block) do
                proc do |o|
                  o.helper name, false
                  o.helper "#{name}=".to_sym, false
                end
              end

              it 'does not define default helpers' do
                is_expected.to be_a_kind_of(Datadog::Core::Configuration::OptionDefinition)
                expect(options_class.options).to include(name)
                expect(options_class.new).to_not respond_to(name)
                expect(options_class.new).to_not respond_to("#{name}=")
              end
            end

            context 'to add a custom helper' do
              let(:custom_helper) { :foobar }
              let(:block) do
                proc do |o|
                  o.helper(custom_helper) { custom_helper }
                end
              end

              it 'defines an additional helper' do
                is_expected.to be_a_kind_of(Datadog::Core::Configuration::OptionDefinition)
                expect(options_class.options).to include(name)
                expect(options_class.new).to respond_to(name)
                expect(options_class.new).to respond_to("#{name}=")
                expect(options_class.new).to respond_to(custom_helper)
              end
            end
          end
        end
      end
    end

    describe 'instance behavior' do
      subject(:options_object) { options_class.new }

      describe '#options' do
        subject(:options) { options_object.options }

        it { is_expected.to be_a_kind_of(Datadog::Core::Configuration::OptionSet) }
      end

      describe '#set_option' do
        subject(:set_option) { options_object.set_option(name, value) }

        let(:name) { :foo }
        let(:value) { double('value') }

        context 'when the option is defined' do
          before { options_class.send(:option, name) }

          it { expect { set_option }.to change { options_object.send(name) }.from(nil).to(value) }
        end

        context 'when the option is not defined' do
          it { expect { set_option }.to raise_error(described_class::InvalidOptionError) }
        end
      end

      describe '#get_option' do
        subject(:get_option) { options_object.get_option(name) }

        let(:name) { :foo }

        context 'when the option is defined' do
          before { options_class.send(:option, name, meta) }

          let(:meta) { {} }

          context 'and a value is set' do
            let(:value) { double('value') }

            before { options_object.set_option(name, value) }

            it { is_expected.to be(value) }
          end

          context 'and a value is not set' do
            let(:meta) { super().merge(default: default_value) }
            let(:default_value) { double('default_value') }

            it { is_expected.to be(default_value) }
          end
        end

        context 'when the option is not defined' do
          it { expect { get_option }.to raise_error(described_class::InvalidOptionError) }
        end
      end

      describe '#reset_option' do
        subject(:reset_option) { options_object.reset_option(name) }

        let(:name) { :foo }

        context 'when the option is defined' do
          before { options_class.send(:option, name, default: default_value) }

          let(:default_value) { double('default_value') }

          context 'and a value is set' do
            let(:value) { double('value') }

            before { options_object.set_option(name, value) }

            it do
              expect { reset_option }.to change { options_object.get_option(name) }
                .from(value)
                .to(default_value)
            end
          end
        end

        context 'when the option is not defined' do
          it { expect { reset_option }.to raise_error(described_class::InvalidOptionError) }
        end
      end

      describe '#option_defined?' do
        subject(:option_defined?) { options_object.option_defined?(name) }

        let(:name) { :foo }

        context 'when no options are defined' do
          it { is_expected.to be false }
        end

        context 'when option is defined' do
          before { options_class.send(:option, name) }

          it { is_expected.to be true }
        end
      end

      describe '#options_hash' do
        subject(:hash) { options_object.options_hash }

        context 'when no options are defined' do
          it { is_expected.to eq({}) }
        end

        context 'when options are set' do
          before do
            options_class.send(:option, :foo)
            options_object.set_option(:foo, :bar)
          end

          it { is_expected.to eq(foo: :bar) }
        end
      end

      describe '#reset_options!' do
        subject(:reset_options) { options_object.reset_options! }

        context 'when an option is defined' do
          let(:option) { options_object.options[:foo] }

          before do
            options_class.send(:option, :foo, default: :bar)
            options_object.set_option(:foo, :baz)
          end

          it 'resets the option to its default value' do
            expect { reset_options }.to change { options_object.get_option(:foo) }.from(:baz).to(:bar)
          end
        end
      end
    end
  end
end
