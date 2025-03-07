require 'spec_helper'

require 'datadog/tracing/metadata/metastruct_tagging'

RSpec.describe Datadog::Tracing::Metadata::MetastructTagging do
  subject(:test_object) { test_class.new }

  let(:test_class) do
    Class.new { include Datadog::Tracing::Metadata::MetastructTagging }
  end

  describe '#set_metastruct_tag' do
    it 'sets the metastruct to a hash with given key / value pair' do
      expect do
        test_object.set_metastruct_tag(:foo, [{ some: 'value' }])
      end.to change { test_object.get_metastruct_tag(:foo) }.from(nil).to([{ some: 'value' }])
    end

    it 'does not lose previous entries' do
      test_object.set_metastruct_tag(:foo, [{ some: 'value' }])

      expect do
        test_object.set_metastruct_tag(:bar, [{ another: 'value' }])
      end.not_to(change { test_object.get_metastruct_tag(:foo) })
    end
  end

  describe '#get_metastruct_tag' do
    it 'returns nil if the key does not exist' do
      expect(test_object.get_metastruct_tag(:foo)).to be_nil
    end
  end
end
