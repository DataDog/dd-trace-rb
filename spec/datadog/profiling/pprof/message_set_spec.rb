require 'spec_helper'

require 'datadog/profiling/pprof/message_set'

RSpec.describe Datadog::Profiling::Pprof::MessageSet do
  subject(:message_set) { described_class.new }

  it { is_expected.to be_a_kind_of(Datadog::Core::Utils::ObjectSet) }

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
