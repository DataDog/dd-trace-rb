require 'spec_helper'

require 'datadog/core/utils/object_set'

RSpec.describe Datadog::Core::Utils::ObjectSet do
  subject(:object_set) { described_class.new }

  describe '::new' do
    context 'given a seed' do
      let(:object_set) { described_class.new(seed) }
      let(:seed) { 100 }

      let(:args) { [rand] }

      it 'yields to the build block' do
        expect { |b| object_set.fetch(*args, &b) }
          .to yield_with_args(seed, *args)
      end
    end

    context 'given a custom key block' do
      let(:object_set) { described_class.new(&key_block) }

      let(:key_block) { proc { |*args| key_builder.build(*args) } }
      let(:key_builder) { double('key_builder') }
      let(:custom_key) { double('custom key') }

      let(:args) { [rand] }

      it 'invokes the block to resolve keys' do
        expect(key_builder).to receive(:build)
          .with(*args)
          .and_return(custom_key)

        object_set.fetch(*args) { :object }
      end
    end
  end

  describe '#fetch' do
    subject(:fetch) { object_set.fetch(*args, &build_block) }

    context 'and unique args are provided' do
      let(:args) { [rand] }
      let(:build_block) { proc { |_id, *_args| object } }

      let(:next_id) { double('next ID') }
      let(:object) { double('object') }

      before do
        expect_any_instance_of(Datadog::Core::Utils::Sequence)
          .to receive(:next)
          .and_return(next_id)
      end

      it 'yields to the build block' do
        expect { |b| object_set.fetch(*args, &b) }
          .to yield_with_args(next_id, *args)
      end

      it 'returns the object' do
        is_expected.to be(object)
      end
    end

    context 'and args matching an existing object are provided' do
      let(:args) { [rand] }
      let(:build_block) { proc { |_id, *_args| object } }

      let(:original_object) { double('original object') }
      let(:object) { double('object') }

      before do
        # Fetch same args to cache object
        object_set.fetch(*args) { original_object }

        expect_any_instance_of(Datadog::Core::Utils::Sequence)
          .to_not receive(:next)
      end

      it 'does not yield to the build block' do
        expect { |b| object_set.fetch(*args, &b) }
          .to_not yield_control
      end

      it 'returns the object' do
        is_expected.to be(original_object)
      end
    end
  end

  describe '#length' do
    subject(:length) { object_set.length }

    it { is_expected.to eq 0 }

    context 'when objects have been added' do
      let(:n) { 3 }

      before { n.times { object_set.fetch(rand) { rand } } }

      it { is_expected.to eq(n) }
    end
  end

  describe '#objects' do
    subject(:objects) { object_set.objects }

    context 'by default' do
      it { is_expected.to eq([]) }
    end

    context 'when objects have been added' do
      let(:object_count) { 3 }

      before do
        object_count.times { object_set.fetch(rand) { double('object') } }
      end

      it do
        is_expected.to be_a_kind_of(Array)
        is_expected.to have(object_count).items
        is_expected.to include(RSpec::Mocks::Double)
      end
    end
  end
end
