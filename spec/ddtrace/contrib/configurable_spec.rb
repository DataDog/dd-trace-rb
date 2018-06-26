require 'spec_helper'

require 'ddtrace'

RSpec.describe Datadog::Contrib::Configurable do
  describe 'implemented' do
    subject(:configurable_class) do
      Class.new.tap do |klass|
        klass.send(:include, described_class)
      end
    end

    describe 'instance behavior' do
      subject(:configurable_object) { configurable_class.new }

      describe '#default_configuration' do
        subject(:configuration) { configurable_object.default_configuration }
        it { is_expected.to be_a_kind_of(Datadog::Contrib::Configuration::Settings) }
      end

      describe '#reset_configuration!' do
        subject(:reset) { configurable_object.reset_configuration! }

        context 'when a configuration has been added' do
          before(:each) { configurable_object.configure(:foo, service_name: 'bar') }

          it do
            expect { reset }.to change { configurable_object.configurations.keys }
              .from([:default, :foo])
              .to([:default])
          end
        end
      end

      describe '#configuration' do
        context 'when no name is provided' do
          subject(:configuration) { configurable_object.configuration }
          it { is_expected.to be_a_kind_of(Datadog::Contrib::Configuration::Settings) }
          it { is_expected.to be(configurable_object.configurations[:default]) }
        end

        context 'when a name is provided' do
          subject(:configuration) { configurable_object.configuration(name) }
          let(:name) { :foo }

          context 'and the configuration exists' do
            before(:each) { configurable_object.configure(:foo, service_name: 'bar') }
            it { is_expected.to be_a_kind_of(Datadog::Contrib::Configuration::Settings) }
            it { is_expected.to be(configurable_object.configurations[:foo]) }
          end

          context 'but the configuration doesn\'t exist' do
            it { is_expected.to be nil }
          end
        end
      end

      describe '#configurations' do
        subject(:configurations) { configurable_object.configurations }

        context 'when nothing has been explicitly configured' do
          it { is_expected.to include(default: a_kind_of(Datadog::Contrib::Configuration::Settings)) }
        end

        context 'when a configuration has been added' do
          before(:each) { configurable_object.configure(:foo, service_name: 'bar') }

          it do
            is_expected.to include(
              default: a_kind_of(Datadog::Contrib::Configuration::Settings),
              foo: a_kind_of(Datadog::Contrib::Configuration::Settings)
            )
          end
        end
      end

      describe '#configure' do
        context 'when provided a name' do
          subject(:configure) { configurable_object.configure(name, service_name: 'bar') }
          let(:name) { :foo }

          context 'that matches an existing configuration' do
            before(:each) { configurable_object.configure(name, service_name: 'baz') }

            it do
              expect { configure }.to change { configurable_object.configuration(name).service_name }
                .from('baz')
                .to('bar')
            end
          end

          context 'that does not match any configuration' do
            it do
              expect { configure }.to change { configurable_object.configuration(name) }
                .from(nil)
                .to(a_kind_of(Datadog::Contrib::Configuration::Settings))
            end
          end
        end
      end
    end
  end
end
