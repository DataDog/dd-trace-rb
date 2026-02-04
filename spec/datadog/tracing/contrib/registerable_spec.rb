require 'datadog/tracing/contrib/support/spec_helper'

require 'datadog'

RSpec.describe Datadog::Tracing::Contrib::Registerable do
  describe 'implemented' do
    subject(:registerable_class) do
      Class.new.tap do |klass|
        klass.include(described_class)
      end
    end

    describe 'class behavior' do
      describe '#register_as' do
        subject(:register_as) { registerable_class.register_as(name, **options) }

        let(:name) { :foo }
        let(:options) { {} }

        context 'when a registry' do
          context 'is provided' do
            let(:options) { {registry: registry} }
            let(:registry) { instance_double(Datadog::Tracing::Contrib::Registry) }

            it do
              expect(registry).to receive(:add)
                .with(name, a_kind_of(registerable_class), false)
              register_as
            end
          end

          context 'is not provided' do
            it do
              expect(Datadog.registry).to receive(:add)
                .with(name, a_kind_of(registerable_class), false)
              register_as
            end
          end
        end

        context 'when auto_patch' do
          context 'is provided' do
            let(:options) { {auto_patch: true} }

            it do
              expect(Datadog.registry).to receive(:add)
                .with(name, a_kind_of(registerable_class), true)
              register_as
            end
          end

          context 'is not provided' do
            it do
              expect(Datadog.registry).to receive(:add)
                .with(name, a_kind_of(registerable_class), false)
              register_as
            end
          end
        end
      end

      describe '#register_as_alias' do
        subject(:register_as_alias) { registerable_class.register_as_alias(:original, :alias, **options) }

        context 'when a registry' do
          context 'is provided' do
            let(:options) { {registry: registry} }
            let(:registry) { Datadog::Tracing::Contrib::Registry.new }

            context 'with the original integration not registered' do
              it { expect { register_as_alias }.to raise_error(ArgumentError) }
            end

            context 'with the original integration registered' do
              before { registerable_class.register_as(:original, registry: registry) }

              it 'creates an alias to the original integration object' do
                register_as_alias
                expect(registry[:alias]).to be(registry[:original])
              end
            end
          end

          context 'is not provided' do
            let(:options) { {} }
            let(:registry) { Datadog::Tracing::Contrib::Registry.new }

            before { registerable_class.register_as(:original, registry: registry) }

            it 'invokes the global Datadog.registry' do
              stub_const('Datadog::Tracing::Contrib::REGISTRY', registry)

              register_as_alias
              expect(registry[:alias]).to be(registry[:original])
            end
          end
        end
      end
    end

    describe 'instance behavior' do
      subject(:registerable_object) { registerable_class.new(name, **options) }

      let(:name) { :foo }
      let(:options) { {} }

      it { is_expected.to have_attributes(name: name) }
    end
  end
end
