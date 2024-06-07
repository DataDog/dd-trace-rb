require 'spec_helper'

require 'datadog'

RSpec.describe Datadog::Core::Configuration::Options do
  describe 'implemented' do
    subject(:options_class) do
      Class.new.tap do |klass|
        klass.include(described_class)
      end
    end

    # When setting the setting value, we make sure to duplicate it to avoid unwanted modifications
    # to make sure specs pass when comparing result ex. expect(result).to be value
    # we ensure that frozen_or_dup returns the same instance
    before do
      allow(Datadog::Core::Utils::SafeDup).to receive(:frozen_or_dup) do |args, _block|
        args
      end
    end

    describe 'class behavior' do
      describe '#options' do
        subject(:options) { options_class.options }

        context 'for a class directly implementing Options' do
          it { is_expected.to be_a(Hash) }
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

            it { is_expected.to be_a(Hash) }
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

        it { is_expected.to be_a(Hash) }
      end

      describe '#set_option' do
        subject(:set_option) { options_object.set_option(name, value) }

        let(:name) { :foo }
        let(:value) { double('value') }

        context 'when the option is defined' do
          before { options_class.send(:option, name) }

          it { expect { set_option }.to change { options_object.send(name) }.from(nil).to(value) }

          it 'defaults to PROGRAMMATIC precedence' do
            set_option

            expect(options_object.options[name].send(:precedence_set))
              .to eq(Datadog::Core::Configuration::Option::Precedence::PROGRAMMATIC)
          end

          context 'with precedence' do
            subject(:set_option) { options_object.set_option(name, value, precedence: precedence) }
            let(:precedence) { Datadog::Core::Configuration::Option::Precedence::REMOTE_CONFIGURATION }

            it 'sets the option precedence' do
              set_option
              expect(options_object.options[name].send(:precedence_set)).to eq(precedence)
            end
          end
        end

        context 'when the option is not defined' do
          it { expect { set_option }.to raise_error(described_class::InvalidOptionError) }
        end
      end

      describe '#unset_option' do
        subject(:unset_option) { options_object.unset_option(name) }

        let(:name) { :foo }

        context 'when the option is defined' do
          before { options_class.send(:option, name) { |o| o.default :test_default } }

          context 'and value is not set' do
            it 'does not change default value' do
              expect { unset_option }.to_not change { options_object.send(name) }.from(:test_default)
            end
          end

          context 'and value is set' do
            before do
              options_object.set_option(
                name,
                :new_value,
                precedence: Datadog::Core::Configuration::Option::Precedence::PROGRAMMATIC
              )
            end

            it 'defaults to PROGRAMMATIC precedence' do
              unset_option
              expect(options_object.get_option(name)).to eq(:test_default)
            end

            context 'with precedence' do
              subject(:unset_option) { options_object.unset_option(name, precedence: precedence) }
              let(:precedence) { Datadog::Core::Configuration::Option::Precedence::REMOTE_CONFIGURATION }

              it 'removes the option with matching precedence' do
                options_object.set_option(
                  name,
                  :should_stay,
                  precedence: Datadog::Core::Configuration::Option::Precedence::PROGRAMMATIC
                )

                options_object.set_option(
                  name,
                  :go_away,
                  precedence: Datadog::Core::Configuration::Option::Precedence::REMOTE_CONFIGURATION
                )

                unset_option

                expect(options_object.get_option(name)).to eq(:should_stay)
              end
            end
          end
        end

        context 'when the option is not defined' do
          it { expect { unset_option }.to raise_error(described_class::InvalidOptionError) }
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

      describe '#using_default?' do
        subject(:using_default?) { options_object.using_default?(name) }

        let(:name) { :foo }

        context 'when the option is defined' do
          before { options_class.send(:option, name, meta) }

          let(:meta) { {} }

          context 'and a value is set' do
            before { options_object.set_option(name, 'something') }

            it { is_expected.to be(false) }
          end

          context 'and a value is not set' do
            context 'and no default value is configured' do
              it { is_expected.to be(true) }
            end

            context 'and a default value is configured' do
              let(:meta) { { default: 'anything' } }

              it { is_expected.to be(true) }

              context 'and an environment variable is configured' do
                let(:meta) { { default: 'anything', env: 'TEST_ENV_VAR' } }

                context 'and an environmet variable is set' do
                  around do |example|
                    ClimateControl.modify('TEST_ENV_VAR' => 'anything') { example.run }
                  end

                  it { is_expected.to be(false) }
                end

                context 'and an environment variable is not set' do
                  it { is_expected.to be(true) }
                end
              end
            end

            context 'an environment variable is configured' do
              let(:meta) { { env: 'TEST_ENV_VAR' } }

              context 'and an environmet variable is set' do
                around do |example|
                  ClimateControl.modify('TEST_ENV_VAR' => 'anything') { example.run }
                end

                it { is_expected.to be(false) }
              end

              context 'and an environment variable is not set' do
                it { is_expected.to be(true) }
              end
            end
          end
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
