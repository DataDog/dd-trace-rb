require 'spec_helper'

require 'ddtrace/transport/http/adapters/registry'

RSpec.describe Datadog::Transport::HTTP::Adapters::Registry do
  subject(:registry) { described_class.new }

  describe '#get' do
    subject(:get) { registry.get(name) }

    let(:name) { double('name') }

    context 'when name' do
      context 'exists' do
        let(:klass) { double('class') }

        before { registry.set(klass, name) }

        it { is_expected.to be klass }
      end

      context 'does not exist' do
        it { is_expected.to be nil }
      end
    end
  end

  describe '#set' do
    let(:klass) { double('class') }

    context 'when given a name' do
      subject(:set) { registry.set(klass, name) }

      let(:name) { double('name') }

      it do
        is_expected.to be klass
        expect(registry.get(name)).to be klass
      end
    end

    context 'when not given a name' do
      subject(:set) { registry.set(klass) }

      let(:name) { double('name') }

      before { allow(klass).to receive(:to_s).and_return(name) }

      it do
        is_expected.to be klass
        expect(registry.get(name)).to be klass
      end
    end
  end
end
