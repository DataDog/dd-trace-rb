require 'spec_helper'

RSpec.describe Datadog::Registry do
  describe 'instance' do
    subject(:registry) { described_class.new }

    describe 'behavior' do
      it { is_expected.to be_a_kind_of(Enumerable) }

      shared_context 'an existing entry' do
        before(:each) { entry }
        let(:entry) { registry.add(name, klass, auto_patch) }
        let(:name) { :foo }
        let(:klass) { double('class') }
        let(:auto_patch) { false }
      end

      describe '#add' do
        subject(:add) { registry.add(name, klass, auto_patch) }

        let(:name) { :foo }
        let(:auto_patch) { false }
        
        context 'when given an class' do
          let(:klass) { double('class') }

          context 'and then the registry is accessed by the same name' do
            subject(:entry) { registry[name] }
            before(:each) { add }
            it { is_expected.to be(klass) }
          end
        end
      end

      describe '#each' do
        context 'when a class has been registered' do
          include_context 'an existing entry'
          it { expect { |b| registry.each(&b) }.to yield_successive_args(entry) }
        end
      end

      describe '#to_h' do
        subject { registry.to_h }

        context 'when no class has been registered' do
          it { is_expected.to eq({}) }
        end

        context 'when a class has been registered' do
          include_context 'an existing entry'

          it do
            is_expected.to match a_hash_including(
              name => auto_patch
            )
          end
        end
      end
    end
  end

  describe Datadog::Registry::Entry do
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
