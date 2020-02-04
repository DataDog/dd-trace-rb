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
        subject(:reset_configuration!) { configurable_object.reset_configuration! }
        it do
          expect { reset_configuration! }.to(change { configurable_object.configuration.object_id })
        end
      end

      describe '#configuration' do
        context 'when no name is provided' do
          subject(:configuration) { configurable_object.configuration }
          it { is_expected.to be_a_kind_of(Datadog::Contrib::Configuration::Settings) }
          it { expect(configuration.service_name).to be nil }
        end

        context 'when a name is provided' do
          subject(:configuration) { configurable_object.configuration(name) }
          let(:name) { :foo }

          context 'and the configuration exists' do
            before { configurable_object.configure(:foo, service_name: 'bar') }
            it { is_expected.to be_a_kind_of(Datadog::Contrib::Configuration::Settings) }
            it { expect(configuration.service_name).to eq('bar') }
          end

          context 'but the configuration doesn\'t exist' do
            it { is_expected.to be_a_kind_of(Datadog::Contrib::Configuration::Settings) }
            it { expect(configuration.service_name).to be nil }
          end
        end
      end

      describe '#configure' do
        context 'when provided a name' do
          subject(:configure) { configurable_object.configure(name, service_name: 'bar') }
          let(:name) { :foo }

          context 'that matches an existing configuration' do
            before { configurable_object.configure(name, service_name: 'baz') }

            it 'updates the configuration' do
              expect { configure }.to change { configurable_object.configuration(name).service_name }
                .from('baz')
                .to('bar')
            end

            it 'reuses the same configuration object' do
              expect { configure }.to_not(change { configurable_object.configuration(name).object_id })
            end
          end

          context 'that does not match any configuration' do
            it do
              expect { configure }.to(change { configurable_object.configuration(name).object_id })
            end
          end
        end
      end
    end
  end
end
