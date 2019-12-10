require 'securerandom'
require 'ddtrace/contrib/rails/ext'

require 'ddtrace/contrib/rails/rails_helper'

RSpec.describe 'Rails cache' do
  include_context 'Rails test application'

  before do
    Datadog.configuration[:rails][:cache_service] = 'rails-cache'
  end

  before { app }

  let(:cache) { Rails.cache }

  let(:key) { 'custom-key' }

  context '#read' do
    subject(:read) { cache.read(key) }

    before { cache.write(key, 50) }

    it do
      expect(read).to eq(50)

      expect(spans).to have(2).items
      get, set = spans
      expect(get.name).to eq('rails.cache')
      expect(get.span_type).to eq('cache')
      expect(get.resource).to eq('GET')
      expect(get.service).to eq('rails-cache')
      expect(get.get_tag('rails.cache.backend').to_s).to eq('file_store')
      expect(get.get_tag('rails.cache.key')).to eq(key)
      expect(set.name).to eq('rails.cache')
    end
  end

  context '#write' do
    subject(:write) { cache.write(key, 50) }

    it do
      write
      expect(span.name).to eq('rails.cache')
      expect(span.span_type).to eq('cache')
      expect(span.resource).to eq('SET')
      expect(span.service).to eq('rails-cache')
      expect(span.get_tag('rails.cache.backend').to_s).to eq('file_store')
      expect(span.get_tag('rails.cache.key')).to eq(key)
    end

    context 'with custom cache_service' do
      before { Datadog.configuration[:rails][:cache_service] = 'service-cache' }

      it 'uses the proper service name' do
        write
        expect(span.service).to eq('service-cache')
      end
    end

    context 'with complex cache key' do
      let(:key) { ['custom-key', %w[x y], user] }
      let(:user) { double('User', cache_key: 'User:3') }

      it 'expands key using ActiveSupport' do
        write
        expect(span.get_tag('rails.cache.key')).to eq('custom-key/x/y/User:3')
      end
    end
  end

  context '#delete' do
    subject!(:delete) { cache.delete(key) }

    it do
      expect(span.name).to eq('rails.cache')
      expect(span.span_type).to eq('cache')
      expect(span.resource).to eq('DELETE')
      expect(span.service).to eq('rails-cache')
      expect(span.get_tag('rails.cache.backend').to_s).to eq('file_store')
      expect(span.get_tag('rails.cache.key')).to eq(key)
    end
  end

  context '#fetch' do
    context 'with exception' do
      subject(:fetch) { cache.fetch('exception') { raise 'oops' } }

      it do
        expect { fetch }.to raise_error(StandardError)

        expect(span.name).to eq('rails.cache')
        expect(span.span_type).to eq('cache')
        expect(span.resource).to eq('GET')
        expect(span.service).to eq('rails-cache')
        expect(span.get_tag('rails.cache.backend').to_s).to eq('file_store')
        expect(span.get_tag('rails.cache.key')).to eq('exception')
        expect(span.get_tag('error.type')).to eq('RuntimeError')
        expect(span.get_tag('error.msg')).to eq('oops')
      end
    end
  end

  context 'with very large cache key' do
    it 'truncates key too large' do
      max_key_size = Datadog::Contrib::ActiveSupport::Ext::QUANTIZE_CACHE_MAX_KEY_SIZE
      large_key = ''.ljust(max_key_size * 2, SecureRandom.hex)
      cache.write(large_key, 'foobar')

      expect(large_key.size).to be > max_key_size
      expect(span.name).to eq('rails.cache')
      expect(span.get_tag('rails.cache.key')).to have(max_key_size).items
      expect(span.get_tag('rails.cache.key')).to end_with('...')
    end
  end
end
