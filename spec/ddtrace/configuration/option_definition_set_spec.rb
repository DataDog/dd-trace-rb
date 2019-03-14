require 'spec_helper'

require 'ddtrace'

RSpec.describe Datadog::Configuration::OptionDefinitionSet do
  subject(:set) { described_class.new }

  it { is_expected.to be_a_kind_of(Hash) }

  shared_context 'dependent option set' do
    before(:each) do
      set[:foo] = instance_double(
        Datadog::Configuration::OptionDefinition,
        depends_on: [:bar]
      )

      set[:bar] = instance_double(
        Datadog::Configuration::OptionDefinition,
        depends_on: [:baz]
      )

      set[:baz] = instance_double(
        Datadog::Configuration::OptionDefinition,
        depends_on: []
      )
    end
  end

  describe '#dependency_order' do
    subject(:dependency_order) { set.dependency_order }

    context 'when invoked' do
      let(:resolver) { instance_double(Datadog::Configuration::DependencyResolver) }

      it do
        expect(Datadog::Configuration::DependencyResolver).to receive(:new)
          .with(a_kind_of(Hash))
          .and_return(resolver)
        expect(resolver).to receive(:call)
        dependency_order
      end
    end

    context 'when given some options' do
      include_context 'dependent option set'
      it { is_expected.to eq([:baz, :bar, :foo]) }
    end
  end

  describe '#dependency_graph' do
    subject(:dependency_graph) { set.dependency_graph }

    context 'when set contains options' do
      include_context 'dependent option set'
      it { is_expected.to eq(foo: [:bar], bar: [:baz], baz: []) }
    end
  end
end
