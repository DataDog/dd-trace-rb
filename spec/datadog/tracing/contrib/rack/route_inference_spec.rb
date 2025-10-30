require 'datadog/tracing/contrib/support/spec_helper'

require 'datadog/tracing/contrib/rack/route_inference'

RSpec.describe Datadog::Tracing::Contrib::Rack::RouteInference do
  describe '.read_or_infer' do
    context 'when inferred route was not yet persisted in request env' do
      let(:env) do
        {
          'SCRIPT_NAME' => '/api',
          'PATH_INFO' => '/users/1'
        }
      end

      it 'returns inferred route' do
        expect(described_class.read_or_infer(env)).to eq('/api/users/{param:int}')
      end

      it 'persists inferred route in request env' do
        expect { described_class.read_or_infer(env) }.to change { env['datadog.inferred_route'] }
          .from(nil).to('/api/users/{param:int}')
      end
    end

    context 'when inferred route already persisted in request env' do
      let(:env) do
        {
          'SCRIPT_NAME' => '/api',
          'PATH_INFO' => '/users/1',
          'datadog.inferred_route' => '/some_route'
        }
      end

      it 'returns persisted inferred route' do
        expect(described_class.read_or_infer(env)).to eq('/some_route')
      end

      it 'does not change inferred route value in request env' do
        expect { described_class.read_or_infer(env) }.not_to change { env['datadog.inferred_route'] }
      end
    end
  end

  describe '.infer' do
    it 'works with an empty path' do
      expect(described_class.infer('/')).to eq('/')
    end

    it 'replaces integer params that have at least 1 digits' do
      expect(described_class.infer('/foo/bar/1/baz')).to eq('/foo/bar/{param:int}/baz')
    end

    it 'replaces integer params that have at least 2 digits and at least 1 separator' do
      expect(described_class.infer('/foo/bar/1-3/baz')).to eq('/foo/bar/{param:int_id}/baz')
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
      expect(described_class.infer('/foo/bar/123/baz/FFF000/345/45-6/qux/567'))
        .to eq('/foo/bar/{param:int}/baz/{param:hex}/{param:int}/{param:int_id}/qux')
    end

    it 'removes empty segments from path' do
      expect(described_class.infer('/foo//1/bar')).to eq('/foo/{param:int}/bar')
    end

    it 'returns nil if a non-string argument is passed' do
      expect(described_class.infer(nil)).to be_nil
    end
  end
end
