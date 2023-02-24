require 'spec_helper'

require 'datadog/profiling/buffer'

RSpec.describe Datadog::Profiling::Buffer do
  subject(:buffer) { described_class.new(max_size) }

  let(:max_size) { 0 }

  it { is_expected.to be_a_kind_of(Datadog::Core::Buffer::ThreadSafe) }

  describe '#cache' do
    subject(:cache) { buffer.cache(name) }

    let(:name) { :test }

    it { is_expected.to be_a_kind_of(Datadog::Core::Utils::ObjectSet) }
  end

  describe '#string_table' do
    subject(:string_table) { buffer.string_table }

    it { is_expected.to be_a_kind_of(Datadog::Core::Utils::StringTable) }
  end

  describe '#pop' do
    subject(:pop) { buffer.pop }

    it 'replaces the string table' do
      expect { pop }
        .to(change { buffer.string_table.object_id })
    end

    it 'replaces caches' do
      expect { pop }
        .to(change { buffer.cache(:test).object_id })
    end
  end
end
