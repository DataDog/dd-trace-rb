require 'spec_helper'

require 'ddtrace/profiling/pprof/message_set'

RSpec.describe Datadog::Profiling::Pprof::MessageSet do
  subject(:message_set) { described_class.new }

  describe '::new' do
    context 'given a seed' do
      let(:message_set) { described_class.new(seed) }
      let(:seed) { 100 }

      let(:args) { [rand] }

      it 'yields to the build block' do
        expect { |b| message_set.fetch(*args, &b) }
          .to yield_with_args(seed, *args)
      end
    end

    context 'given a custom key block' do
      let(:message_set) { described_class.new(&key_block) }

      let(:key_block) { proc { |*args| key_builder.build(*args) } }
      let(:key_builder) { double('key_builder') }
      let(:custom_key) { double('custom key') }

      let(:args) { [rand] }

      it 'invokes the block to resolve keys' do
        expect(key_builder).to receive(:build)
          .with(*args)
          .and_return(custom_key)

        message_set.fetch(*args) { :message }
      end
    end
  end

  describe '#fetch' do
    subject(:fetch) { message_set.fetch(*args, &build_block) }

    context 'and unique args are provided' do
      let(:args) { [rand] }
      let(:build_block) { proc { |_id, *_args| message } }

      let(:next_id) { double('next ID') }
      let(:message) { double('message') }

      before do
        expect_any_instance_of(Datadog::Utils::Sequence)
          .to receive(:next)
          .and_return(next_id)
      end

      it 'yields to the build block' do
        expect { |b| message_set.fetch(*args, &b) }
          .to yield_with_args(next_id, *args)
      end

      it 'returns the message' do
        is_expected.to be(message)
      end
    end

    context 'and args matching an existing message are provided' do
      let(:args) { [rand] }
      let(:build_block) { proc { |_id, *_args| message } }

      let(:original_message) { double('original message') }
      let(:message) { double('message') }

      before do
        # Fetch same args to cache message
        message_set.fetch(*args) { original_message }

        expect_any_instance_of(Datadog::Utils::Sequence)
          .to_not receive(:next)
      end

      it 'does not yield to the build block' do
        expect { |b| message_set.fetch(*args, &b) }
          .to_not yield_control
      end

      it 'returns the message' do
        is_expected.to be(original_message)
      end
    end
  end

  describe '#length' do
    subject(:length) { message_set.length }
    it { is_expected.to eq 0 }

    context 'when messages have been added' do
      let(:n) { 3 }
      before { n.times { message_set.fetch(rand) { rand } } }
      it { is_expected.to eq(n) }
    end
  end

  describe '#messages' do
    subject(:messages) { message_set.messages }

    context 'by default' do
      it { is_expected.to eq([]) }
    end

    context 'when messages have been added' do
      let(:message_count) { 3 }

      before do
        message_count.times { message_set.fetch(rand) { double('message') } }
      end

      it do
        is_expected.to be_a_kind_of(Array)
        is_expected.to have(message_count).items
        is_expected.to include(RSpec::Mocks::Double)
      end
    end
  end
end
