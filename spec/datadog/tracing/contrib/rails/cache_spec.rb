require 'spec_helper'
require 'datadog/tracing/contrib/analytics_examples'

require 'securerandom'
require 'datadog/tracing/contrib/rails/ext'

require 'datadog/tracing/contrib/rails/rails_helper'

RSpec.describe 'Rails cache' do
  include_context 'Rails test application'

  before do
    Datadog.configuration.tracing[:active_support][:cache_service] = 'rails-cache'
  end

  after do
    Datadog.configuration.tracing[:active_support].reset!
  end

  before { app }

  let(:cache) { Rails.cache }

  let(:key) { 'custom-key' }
  let(:multi_keys) { %w[custom-key-1 custom-key-2 custom-key-3] }

  shared_examples 'a no-op when instrumentation is disabled' do
    context 'disabled at integration level' do
      before { Datadog.configuration.tracing[:active_support].enabled = false }
      after { Datadog.configuration.tracing[:active_support].reset! }

      it 'does not instrument' do
        expect { subject }.to_not(change { fetch_spans })
      end
    end

    context 'disabled at tracer level' do
      before do
        Datadog.configure do |c|
          c.tracing.enabled = false
        end
      end

      after { Datadog.configuration.tracing.reset! }

      it 'does not instrument' do
        expect { subject }.to_not(change { fetch_spans })
      end
    end
  end

  describe '#read' do
    subject(:read) { cache.read(key) }

    before { cache.write(key, 50) }

    it_behaves_like 'a no-op when instrumentation is disabled'

    it_behaves_like 'measured span for integration', false do
      before { read }

      let(:span) { spans.first }
    end

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

      expect(get.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT))
        .to eq('active_support')
      expect(get.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
        .to eq('cache')
      expect(get.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_SERVICE))
        .to eq('rails-cache')

      expect(set.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT))
        .to eq('active_support')
      expect(set.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
        .to eq('cache')
      expect(set.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_SERVICE))
        .to eq('rails-cache')
    end
  end

  describe '#read_multi' do
    subject(:read_multi) { cache.read_multi(*multi_keys) }

    before { multi_keys.each { |key| cache.write(key, 50 + key[-1].to_i) } }

    it_behaves_like 'a no-op when instrumentation is disabled'

    it_behaves_like 'measured span for integration', false do
      before { read_multi }

      let(:span) { spans[0] }
    end

    it do
      expect(read_multi).to eq(Hash[multi_keys.zip([51, 52, 53])])
      expect(spans).to have(1 + multi_keys.size).items
      get = spans[0]
      expect(get.name).to eq('rails.cache')
      expect(get.span_type).to eq('cache')
      expect(get.resource).to eq('MGET')
      expect(get.service).to eq('rails-cache')
      expect(get.get_tag('rails.cache.backend').to_s).to eq('file_store')
      expect(JSON.parse(get.get_tag('rails.cache.keys'))).to eq(multi_keys)
      expect(get.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT))
        .to eq('active_support')
      expect(get.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
        .to eq('cache')
      expect(get.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_SERVICE))
        .to eq('rails-cache')

      spans[1..-1].each do |set|
        expect(set.name).to eq('rails.cache')
        expect(set.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT))
          .to eq('active_support')
        expect(set.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
          .to eq('cache')
        expect(set.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_SERVICE))
          .to eq('rails-cache')
      end
    end
  end

  describe '#write' do
    subject(:write) { cache.write(key, 50) }

    it_behaves_like 'a no-op when instrumentation is disabled'

    it_behaves_like 'measured span for integration', false do
      before { write }
    end

    it do
      write
      expect(span.name).to eq('rails.cache')
      expect(span.span_type).to eq('cache')
      expect(span.resource).to eq('SET')
      expect(span.service).to eq('rails-cache')
      expect(span.get_tag('rails.cache.backend').to_s).to eq('file_store')
      expect(span.get_tag('rails.cache.key')).to eq(key)

      expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT))
        .to eq('active_support')
      expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
        .to eq('cache')
      expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_SERVICE))
        .to eq('rails-cache')
    end

    context 'with custom cache_service' do
      before { Datadog.configuration.tracing[:active_support][:cache_service] = 'service-cache' }

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

  describe '#write_multi' do
    let(:values) { multi_keys.map { |k| 50 + k[-1].to_i } }

    subject(:write_multi) { cache.write_multi(Hash[multi_keys.zip(values)], opt_name: :opt_value) }

    context 'when the method is defined' do
      before do
        unless ::ActiveSupport::Cache::Store.public_method_defined?(:write_multi)
          skip 'Test is not applicable to this Rails version'
        end
      end

      it_behaves_like 'a no-op when instrumentation is disabled'

      it_behaves_like 'measured span for integration', false do
        before { write_multi }
      end

      it do
        write_multi
        expect(span.name).to eq('rails.cache')
        expect(span.span_type).to eq('cache')
        expect(span.resource).to eq('MSET')
        expect(span.service).to eq('rails-cache')
        expect(span.get_tag('rails.cache.backend').to_s).to eq('file_store')
        expect(JSON.parse(span.get_tag('rails.cache.keys'))).to eq(multi_keys)

        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT))
          .to eq('active_support')
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
          .to eq('cache')
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_SERVICE))
          .to eq('rails-cache')
      end

      context 'with custom cache_service' do
        before { Datadog.configuration.tracing[:active_support][:cache_service] = 'service-cache' }

        it 'uses the proper service name' do
          write_multi
          expect(span.service).to eq('service-cache')
        end
      end

      context 'with complex cache key' do
        let(:key) { ['custom-key', %w[x y], user] }
        let(:user) { double('User', cache_key: 'User:3') }

        it 'expands key using ActiveSupport' do
          cache.write_multi(key => 0)
          expect(span.get_tag('rails.cache.keys')).to eq('["custom-key/x/y/User:3"]')
        end
      end
    end

    context 'when the method is not defined' do
      before do
        if ::ActiveSupport::Cache::Store.public_method_defined?(:write_multi)
          skip 'Test is not applicable to this Rails version'
        end
      end

      it do
        expect(::ActiveSupport::Cache::Store.ancestors).not_to(
          include(::Datadog::Tracing::Contrib::ActiveSupport::Cache::Instrumentation::WriteMulti)
        )
      end

      it do
        expect { subject }.to raise_error NoMethodError
      end
    end
  end

  describe '#delete' do
    subject(:delete) { cache.delete(key) }

    it_behaves_like 'a no-op when instrumentation is disabled'
    it_behaves_like 'measured span for integration', false do
      before { delete }
    end

    it do
      delete
      expect(span.name).to eq('rails.cache')
      expect(span.span_type).to eq('cache')
      expect(span.resource).to eq('DELETE')
      expect(span.service).to eq('rails-cache')
      expect(span.get_tag('rails.cache.backend').to_s).to eq('file_store')
      expect(span.get_tag('rails.cache.key')).to eq(key)

      expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT))
        .to eq('active_support')
      expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
        .to eq('cache')
      expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_SERVICE))
        .to eq('rails-cache')
    end
  end

  describe '#fetch' do
    subject(:fetch) { cache.fetch(key) { 'default' } }

    it_behaves_like 'a no-op when instrumentation is disabled'

    it_behaves_like 'measured span for integration', false do
      before { fetch }
      # Choose either GET or SET span

      let(:span) { spans.sample }
    end

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
        expect(span.get_tag('error.message')).to eq('oops')

        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT))
          .to eq('active_support')
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
          .to eq('cache')
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_SERVICE))
          .to eq('rails-cache')
      end
    end
  end

  describe '#fetch_multi' do
    subject(:fetch_multi) { cache.fetch_multi(*multi_keys, expires_in: 42) { |key| 50 + key[-1].to_i } }

    context 'when the method is defined' do
      before do
        unless ::ActiveSupport::Cache::Store.public_method_defined?(:fetch_multi)
          skip 'Test is not applicable to this Rails version'
        end
      end

      it_behaves_like 'a no-op when instrumentation is disabled'

      it_behaves_like 'measured span for integration', false do
        before { fetch_multi }
        # Choose either GET or SET span

        let(:span) { spans.sample }
      end

      context 'with exception' do
        subject(:fetch_multi) { cache.fetch_multi('exception', 'another', 'one') { raise 'oops' } }

        it do
          expect { fetch_multi }.to raise_error(StandardError)
          expect(span.name).to eq('rails.cache')
          expect(span.span_type).to eq('cache')
          expect(span.resource).to eq('MGET')
          expect(span.service).to eq('rails-cache')
          expect(span.get_tag('rails.cache.backend').to_s).to eq('file_store')
          expect(span.get_tag('rails.cache.keys')).to eq('["exception", "another", "one"]')
          expect(span.get_tag('error.type')).to eq('RuntimeError')
          expect(span.get_tag('error.message')).to eq('oops')

          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT))
            .to eq('active_support')
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
            .to eq('cache')
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_SERVICE))
            .to eq('rails-cache')
        end
      end
    end

    context 'when the method is not defined' do
      before do
        if ::ActiveSupport::Cache::Store.public_method_defined?(:fetch_multi)
          skip 'Test is not applicable to this Rails version'
        end
      end

      it do
        expect(::ActiveSupport::Cache::Store.ancestors).not_to(
          include(::Datadog::Tracing::Contrib::ActiveSupport::Cache::Instrumentation::FetchMulti)
        )
      end

      it do
        expect { subject }.to raise_error NoMethodError
      end
    end
  end

  context 'with very large cache key' do
    it 'truncates key too large' do
      max_key_size = Datadog::Tracing::Contrib::ActiveSupport::Ext::QUANTIZE_CACHE_MAX_KEY_SIZE
      large_key = ''.ljust(max_key_size * 2, SecureRandom.hex)
      cache.write(large_key, 'foobar')

      expect(large_key.size).to be > max_key_size
      expect(span.name).to eq('rails.cache')
      expect(span.get_tag('rails.cache.key')).to have(max_key_size).items
      expect(span.get_tag('rails.cache.key')).to end_with('...')

      expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT))
        .to eq('active_support')
      expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION))
        .to eq('cache')
      expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_PEER_SERVICE))
        .to eq('rails-cache')
    end
  end
end
