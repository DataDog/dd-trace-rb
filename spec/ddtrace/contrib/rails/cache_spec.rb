require 'securerandom'
require 'ddtrace/contrib/rails/ext'

require 'ddtrace/contrib/rails/rails_helper'

# TODO better method names and RSpec contexts
RSpec.describe 'Rails application' do
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

  it 'cache.read() is properly traced' do
    # use the cache and assert the proper span
    Rails.cache.write('custom-key', 50)
    value = Rails.cache.read('custom-key')
    expect(value).to eq(50)

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

  it 'cache.write() is properly traced' do
    # use the cache and assert the proper span
    Rails.cache.write('custom-key', 50)

    expect(span.name).to eq('rails.cache')
    expect(span.span_type).to eq('cache')
    expect(span.resource).to eq('SET')
    expect(span.service).to eq('rails-cache')
    expect(span.get_tag('rails.cache.backend').to_s).to eq('file_store')
    expect(span.get_tag('rails.cache.key')).to eq('custom-key')
  end

  it 'cache.delete() is properly traced' do
    # use the cache and assert the proper span
    Rails.cache.delete('custom-key')

    expect(span.name).to eq('rails.cache')
    expect(span.span_type).to eq('cache')
    expect(span.resource).to eq('DELETE')
    expect(span.service).to eq('rails-cache')
    expect(span.get_tag('rails.cache.backend').to_s).to eq('file_store')
    expect(span.get_tag('rails.cache.key')).to eq('custom-key')
  end

  it 'cache exception handling' do
    # use the cache and assert the proper span
    expect { Rails.cache.fetch('exception') { raise 'oops' } }.to raise_error

    expect(span.name).to eq('rails.cache')
    expect(span.span_type).to eq('cache')
    expect(span.resource).to eq('GET')
    expect(span.service).to eq('rails-cache')
    expect(span.get_tag('rails.cache.backend').to_s).to eq('file_store')
    expect(span.get_tag('rails.cache.key')).to eq('exception')
    expect(span.get_tag('error.type')).to eq('RuntimeError')
    expect(span.get_tag('error.msg')).to eq('oops')
  end

  it 'doing a cache call uses the proper service name if it is changed' do
    # update database configuration
    update_config(:cache_service, 'service-cache')

    # make the cache write and assert the proper spans
    Rails.cache.write('custom-key', 50)

    expect(span.service).to eq('service-cache')

    # reset the original configuration
    reset_config
  end

  it 'test_cache_key_truncation_regression' do
    max_key_size = Datadog::Contrib::ActiveSupport::Ext::QUANTIZE_CACHE_MAX_KEY_SIZE
    large_key = ''.ljust(max_key_size * 2, SecureRandom.hex)
    Rails.cache.write(large_key, 'foobar')

    expect(large_key.size).to be > max_key_size
    expect(span.name).to eq('rails.cache')
    expect(span.get_tag('rails.cache.key')).to have(max_key_size).items
    expect(span.get_tag('rails.cache.key')).to end_with('...')
  end

  it 'cache key is expanded using ActiveSupport' do
    class User
      def cache_key
        'User:3'
      end
    end

    Rails.cache.write(['custom-key', %w[x y], User.new], 50)

    expect(span.get_tag('rails.cache.key')).to eq('custom-key/x/y/User:3')
  end
end
