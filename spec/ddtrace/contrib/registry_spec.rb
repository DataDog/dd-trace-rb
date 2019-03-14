require 'spec_helper'

require 'ddtrace'

RSpec.describe Datadog::Contrib::Registry do
  describe 'instance' do
    subject(:registry) { described_class.new }

    describe 'behavior' do
      it { is_expected.to be_a_kind_of(Enumerable) }

      describe '#add' do
        let(:name) { 'foo' }
        let(:klass) { Class.new }
        let(:auto_patch) { false }

        context 'when given an entry to the registry' do
          it do
            entry = registry.add(name, klass, auto_patch)
            expect(entry).to be_an_instance_of(described_class::Entry)
            expect(registry[name]).to eq(klass)
          end
        end
      end

      describe '#each' do
        let(:spy) { [] }
        it do
          entry_one = registry.add(:foo, double('foo class'), true)
          entry_two = registry.add(:bar, double('bar class'), true)
          registry.each { |entry| spy << entry }
          expect(spy).to include(entry_one, entry_two)
        end
      end

      describe '#to_h' do
        it do
          registry.add(:foo, double('foo class'), true)
          expect(registry.to_h).to match a_hash_including(foo: true)
        end
      end
    end
  end

  describe Datadog::Contrib::Registry::Entry do
    describe 'instance' do
      subject(:entry) { described_class.new(name, klass, auto_patch) }

      let(:name) { :foo }
      let(:klass) { double('class') }
      let(:auto_patch) { true }

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

            describe '#auto_patch' do
              subject { entry.auto_patch }
              it { is_expected.to eq(auto_patch) }
            end
          end
        end
      end
    end
  end
end
