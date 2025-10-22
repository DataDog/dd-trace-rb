require 'datadog/tracing/contrib/support/spec_helper'

require 'datadog/tracing/contrib/rack/route_from_path_inference'

RSpec.describe Datadog::Tracing::Contrib::Rack::RouteFromPathInference do
  describe '.infer' do
    it 'works with an empty path' do
      expect(described_class.infer('/')).to eq('/')
    end

    it 'replaces integer params that have at least 2 digits' do
      expect(described_class.infer('/foo/bar/123/baz')).to eq('/foo/bar/{param:int}/baz')
    end

    it 'replaces integer params that have at least 2 digits and at least 1 separator' do
      expect(described_class.infer('/foo/bar/12-3/baz')).to eq('/foo/bar/{param:int_id}/baz')
    end

    it 'replaces params containing at least 6 hexadecimal digits' do
      expect(described_class.infer('/foo/bar/FFF111')).to eq('/foo/bar/{param:hex}')
    end

    it 'replaces params containing at least 6 hexadecimal digits and at least 1 separator' do
      expect(described_class.infer('/foo/bar/FFF-111')).to eq('/foo/bar/{param:hex_id}')
    end

    it 'replaces params containing strings that are at least 20 characters long' do
      expect(described_class.infer('/foo/bar/someridiculouslylongstring')).to eq('/foo/bar/{param:str}')
    end

    it 'only replaces matches in first 8 segments' do
      expect(described_class.infer('/foo/bar/123/baz/FFF000/345/45-6/qux/567')).
        to eq('/foo/bar/{param:int}/baz/{param:hex}/{param:int}/{param:int_id}/qux/567')
    end

    it 'returns nil if a non-string argument is passed' do
      expect(described_class.infer(nil)).to be_nil
    end
  end
end
