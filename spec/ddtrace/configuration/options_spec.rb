require 'spec_helper'

require 'ddtrace'

RSpec.describe Datadog::Configuration::Options do
  describe 'implemented' do
    subject(:options_class) do
      Class.new.tap do |klass|
        klass.send(:include, described_class)
      end
    end

    describe 'class behavior' do
      describe '#options' do
        subject(:options) { options_class.options }

        context 'for a class directly implementing Options' do
          it { is_expected.to be_a_kind_of(Datadog::Configuration::OptionDefinitionSet) }
        end

        context 'on class inheriting from a class implementing Options' do
          let(:parent_class) do
            Class.new.tap do |klass|
              klass.send(:include, described_class)
            end
          end
          let(:options_class) { Class.new(parent_class) }

          context 'which defines some options' do
            before(:each) { parent_class.send(:option, :foo) }

            it { is_expected.to be_a_kind_of(Datadog::Configuration::OptionDefinitionSet) }
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
          is_expected.to be_a_kind_of(Datadog::Configuration::OptionDefinition)
          expect(options_class.options).to include(name)
          expect(options_class.new).to respond_to(name)
          expect(options_class.new).to respond_to("#{name}=")
        end
      end
    end

    describe 'instance behavior' do
      subject(:options_object) { options_class.new }

      describe '#options' do
        subject(:options) { options_object.options }
        it { is_expected.to be_a_kind_of(Datadog::Configuration::OptionSet) }
      end

      describe '#set_option' do
        subject(:set_option) { options_object.set_option(name, value) }
        let(:name) { :foo }
        let(:value) { double('value') }

        context 'when the option is defined' do
          before(:each) { options_class.send(:option, name) }
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
          before(:each) { options_class.send(:option, name, meta) }
          let(:meta) { {} }

          context 'and a value is set' do
            let(:value) { double('value') }
            before(:each) { options_object.set_option(name, value) }
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

      describe '#to_h' do
        subject(:hash) { options_object.to_h }

        context 'when no options are defined' do
          it { is_expected.to eq({}) }
        end

        context 'when options are set' do
          before(:each) do
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

          before(:each) do
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
