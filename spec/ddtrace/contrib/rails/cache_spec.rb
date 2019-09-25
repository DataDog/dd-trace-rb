require 'securerandom'
require 'ddtrace/contrib/rails/ext'

require 'ddtrace/contrib/rails/rails_helper'

# TODO better method names and RSpec contexts
RSpec.describe 'Rails cache' do
  include_context 'Rails test application'
  include_context 'Tracer'

  before do
    @original_tracer = Datadog.configuration[:rails][:tracer]
    Datadog.configuration[:rails][:cache_service] = 'rails-cache'
    Datadog.configuration[:rails][:tracer] = tracer
  end

  after do
    Datadog.configuration[:rails][:tracer] = @original_tracer
  end

  before { app }

  context '#read' do
    subject(:read) { Rails.cache.read('custom-key') }

    before { Rails.cache.write('custom-key', 50) }

    it do
      expect(read).to eq(50)

      expect(spans).to have(2).items
      get, set = spans
      expect(get.name).to eq('rails.cache')
      expect(get.span_type).to eq('cache')
      expect(get.resource).to eq('GET')
      expect(get.service).to eq('rails-cache')
      expect(get.get_tag('rails.cache.backend').to_s).to eq('file_store')
      expect(get.get_tag('rails.cache.key')).to eq('custom-key')
      expect(set.name).to eq('rails.cache')
    end
  end

  context '#write' do
    subject(:write) { Rails.cache.write(key, 50) }
    let(:key) { 'custom-key' }

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
      before { update_config(:cache_service, 'service-cache') }
      after { reset_config }

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
    subject!(:delete) { Rails.cache.delete('custom-key') }

    it do
      expect(span.name).to eq('rails.cache')
      expect(span.span_type).to eq('cache')
      expect(span.resource).to eq('DELETE')
      expect(span.service).to eq('rails-cache')
      expect(span.get_tag('rails.cache.backend').to_s).to eq('file_store')
      expect(span.get_tag('rails.cache.key')).to eq('custom-key')
    end
  end

  context '#fetch' do
    context 'with exception' do
      subject(:fetch) { Rails.cache.fetch('exception') { raise 'oops' } }

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
      Rails.cache.write(large_key, 'foobar')

      expect(large_key.size).to be > max_key_size
      expect(span.name).to eq('rails.cache')
      expect(span.get_tag('rails.cache.key')).to have(max_key_size).items
      expect(span.get_tag('rails.cache.key')).to end_with('...')
    end
  end
end
