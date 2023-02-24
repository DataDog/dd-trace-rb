require 'datadog/tracing/contrib/support/spec_helper'

require 'ddtrace'

RSpec.describe Datadog::Tracing::Contrib::Configurable do
  describe 'implemented' do
    subject(:configurable_class) do
      Class.new.tap do |klass|
        klass.include(described_class)
      end
    end

    describe 'instance behavior' do
      subject(:configurable_object) { configurable_class.new }

      describe '#default_configuration' do
        subject(:default_configuration) { configurable_object.default_configuration }

        it { is_expected.to be_a_kind_of(Datadog::Tracing::Contrib::Configuration::Settings) }

        it 'defaults to being enabled' do
          expect(default_configuration[:enabled]).to be true
        end
      end

      describe '#reset_configuration!' do
        subject(:reset_configuration!) { configurable_object.reset_configuration! }

        it 'generates a new default configuration' do
          expect { reset_configuration! }.to(change { configurable_object.configuration })
        end

        context 'when a configuration has been added' do
          before { configurable_object.configure(:foo, service_name: 'bar') }

          it do
            expect { reset_configuration! }.to change { configurable_object.configurations.keys }
              .from(match_array([:default, :foo]))
              .to([:default])
          end
        end
      end

      describe '#configuration' do
        context 'when no key is provided' do
          subject(:configuration) { configurable_object.configuration }

          it { is_expected.to be_a_kind_of(Datadog::Tracing::Contrib::Configuration::Settings) }
          it { is_expected.to be(configurable_object.configurations[:default]) }
        end

        context 'when a key is provided' do
          subject(:configuration) { configurable_object.configuration(key) }

          let(:key) { :foo }

          context 'and the configuration exists' do
            before { configurable_object.configure(:foo, service_name: 'bar') }

            it { is_expected.to be_a_kind_of(Datadog::Tracing::Contrib::Configuration::Settings) }
            it { is_expected.to be(configurable_object.configurations[:foo]) }
          end

          context 'but the configuration doesn\'t exist' do
            it { is_expected.to be_a_kind_of(Datadog::Tracing::Contrib::Configuration::Settings) }
            it { is_expected.to be(configurable_object.configurations[:default]) }
          end
        end
      end

      describe '#configurations' do
        subject(:configurations) { configurable_object.configurations }

        context 'when nothing has been explicitly configured' do
          it { is_expected.to include(default: a_kind_of(Datadog::Tracing::Contrib::Configuration::Settings)) }
        end

        context 'when a configuration has been added' do
          before { configurable_object.configure(:foo, service_name: 'bar') }

          it do
            is_expected.to include(
              default: a_kind_of(Datadog::Tracing::Contrib::Configuration::Settings),
              foo: a_kind_of(Datadog::Tracing::Contrib::Configuration::Settings)
            )
          end
        end
      end

      describe '#configure' do
        context 'when provided a key' do
          subject(:configure) { configurable_object.configure(key, service_name: 'bar') }

          let(:key) { :foo }

          context 'as nil or :default' do
            [nil, :default].each do |k|
              let(:key) { k }

              it 'reuses the default configuration object' do
                expect { configure }.to_not(change { configurable_object.configuration(key) })
                expect(configurable_object.configuration(key)).to be(configurable_object.configuration(:default))
                expect(configurable_object.configuration(:default).service_name).to eq('bar')
              end
            end
          end

          context 'that matches an existing configuration' do
            before { configurable_object.configure(key, service_name: 'baz') }

            it 'updates the configuration' do
              expect { configure }.to change { configurable_object.configuration(key).service_name }
                .from('baz')
                .to('bar')
            end

            it 'reuses the same configuration object' do
              expect { configure }.to_not(change { configurable_object.configuration(key) })
            end
          end

          context 'that does not match any configuration' do
            it do
              expect { configure }.to(change { configurable_object.configuration(key) })
            end
          end
        end
      end
    end
  end
end
