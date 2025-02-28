require 'datadog/tracing/contrib/support/spec_helper'

require 'datadog'

RSpec.describe Datadog::Tracing::Contrib::Registry do
  describe 'instance' do
    subject(:registry) { described_class.new }

    describe 'behavior' do
      it { is_expected.to be_a_kind_of(Enumerable) }

      describe '#add' do
        let(:name) { 'foo' }
        let(:klass) { Class.new }

        context 'when given an entry to the registry' do
          it do
            entry = registry.add(name, klass)
            expect(entry).to be_an_instance_of(described_class::Entry)
            expect(registry[name]).to eq(klass)
          end
        end
      end

      describe '#each' do
        let(:spy) { [] }

        it do
          entry_one = registry.add(:foo, double('foo class'))
          entry_two = registry.add(:bar, double('bar class'))
          registry.each { |entry| spy << entry }
          expect(spy).to include(entry_one, entry_two)
        end
      end
    end
  end

  describe Datadog::Tracing::Contrib::Registry::Entry do
    describe 'instance' do
      subject(:entry) { described_class.new(name, klass) }

      let(:name) { :foo }
      let(:klass) { double('class') }

      describe 'behavior' do
        describe '#initialize' do
          describe 'returns an entry with' do
            describe '#name' do
              subject { entry.name }

              it { is_expected.to eq(name) }
            end

            describe '#klass' do
              subject { entry.klass }

              it { is_expected.to be(klass) }
            end
          end
        end
      end
    end
  end
end
