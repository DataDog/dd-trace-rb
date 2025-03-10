require 'spec_helper'

require 'datadog/tracing/metadata/metastruct_tagging'

RSpec.describe Datadog::Tracing::Metadata::MetastructTagging do
  subject(:object) { test_class.new }

  let(:test_class) do
    Class.new { include Datadog::Tracing::Metadata::MetastructTagging }
  end

  describe '#set_metastruct_tag' do
    it 'sets the metastruct to a hash with given key / value pair' do
      expect { object.set_metastruct_tag(:foo, [{ some: 'value' }]) }
        .to change { object.get_metastruct_tag(:foo) }.from(nil).to([{ some: 'value' }])
    end

    it 'does not lose previous entries' do
      object.set_metastruct_tag(:foo, [{ some: 'value' }])

      expect { object.set_metastruct_tag(:bar, [{ another: 'value' }]) }
        .not_to(change { object.get_metastruct_tag(:foo) })
    end
  end

  describe '#get_metastruct_tag' do
    it 'returns nil if the key does not exist' do
      expect(object.get_metastruct_tag(:foo)).to be_nil
    end
  end
end
