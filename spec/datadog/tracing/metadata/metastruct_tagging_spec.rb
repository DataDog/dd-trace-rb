require 'spec_helper'

require 'datadog/tracing/metadata/metastruct_tagging'

RSpec.describe Datadog::Tracing::Metadata::MetastructTagging do
  subject(:test_object) { test_class.new }

  let(:test_class) do
    Class.new { include Datadog::Tracing::Metadata::MetastructTagging }
  end

  describe '#set_metastruct_tag' do
    it 'sets the metastruct to a hash with given key / value pair' do
      test_object.set_metastruct_tag(:foo, [{ some: 'value' }])

      expect(test_object.get_metastruct_tag(:foo)).to eq([{ some: 'value' }])
    end

    it 'does not lose previous entries' do
      test_object.instance_variable_set(:@metastruct, { bar: [1] })

      test_object.set_metastruct_tag(:foo, [{ some: 'value' }])

      expect(test_object.get_metastruct_tag(:bar)).to eq([1])
      expect(test_object.get_metastruct_tag(:foo)).to eq([{ some: 'value' }])
    end
  end

  describe '#get_metastruct_tag' do
    it 'returns nil if the key does not exist' do
      expect(test_object.get_metastruct_tag(:foo)).to be_nil
    end
  end
end
