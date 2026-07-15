require 'spec_helper'
require 'datadog/tracing/contrib/active_support/cache/instrumentation'

RSpec.describe Datadog::Tracing::Contrib::ActiveSupport::Cache::Instrumentation do
  describe Datadog::Tracing::Contrib::ActiveSupport::Cache::Instrumentation::PreserveOriginalKey do
    subject(:store) { store_class.new }

    let(:store_class) do
      Class.new do
        def normalize_key(key, options)
          "normalized:#{key}"
        end
      end.tap { |klass| klass.prepend(Datadog::Tracing::Contrib::ActiveSupport::Cache::Instrumentation::PreserveOriginalKey) }
    end

    let(:options) { {} }

    describe '#normalize_key' do
      subject(:normalize_key) { store.normalize_key(key, options) }

      let(:key) { 'custom-key' }

      it 'stores the original key in the options hash' do
        expect { normalize_key }.to change { options[:dd_original_keys] }.from(nil).to('custom-key' => true)
      end

      it 'returns the normalized key' do
        is_expected.to eq('normalized:custom-key')
      end

      context 'when the same key is normalized twice with the same options' do
        it 'does not duplicate the key' do
          store.normalize_key(key, options)

          expect { normalize_key }.to_not(change { options[:dd_original_keys] })
        end
      end

      context 'with multiple distinct keys' do
        it 'stores all keys in insertion order' do
          store.normalize_key('custom-key-1', options)
          store.normalize_key('custom-key-2', options)

          expect(options[:dd_original_keys].keys).to eq(['custom-key-1', 'custom-key-2'])
        end
      end
    end
  end
end
