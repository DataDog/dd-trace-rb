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
            let(:options) { { registry: registry } }
            let(:registry) { instance_double(Datadog::Tracing::Contrib::Registry) }

            it do
              expect(registry).to receive(:add)
                .with(name, a_kind_of(registerable_class))
              register_as
            end
          end

          context 'is not provided' do
            it do
              expect(Datadog.registry).to receive(:add)
                .with(name, a_kind_of(registerable_class))
              register_as
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
