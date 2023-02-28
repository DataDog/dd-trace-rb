require 'concurrent/future'

require 'datadog/tracing/contrib/support/spec_helper'
require 'ddtrace'
require 'spec/support/thread_helpers'

RSpec.describe 'ConcurrentRuby integration tests' do
  # DEV We save an unmodified copy of Concurrent::Future.
  let!(:unmodified_future) { ::Concurrent::Future.dup }
  let(:configuration_options) { {} }
  let(:outer_span) { spans.find { |s| s.name == 'outer_span' } }
  let(:inner_span) { spans.find { |s| s.name == 'inner_span' } }

  before(:context) do
    # Execute an async future to force the eager creation of internal
    # global threads that are never closed.
    #
    # This allows us to separate internal concurrent-ruby threads
    # from ddtrace threads for leak detection.
    ThreadHelpers.with_leaky_thread_creation(:concurrent_ruby) do
      Concurrent::Future.execute {}.value
    end
  end

  # DEV We then restore Concurrent::Future, a dangerous game.
  after do
    ::Concurrent.send(:remove_const, :Future)
    ::Concurrent.const_set('Future', unmodified_future)
    remove_patch!(:concurrent_ruby)
  end

  subject(:deferred_execution) do
    outer_span = tracer.trace('outer_span')
    future = Concurrent::Future.new do
      tracer.trace('inner_span') {}
    end
    future.execute

    future.wait
    outer_span.finish
  end

  shared_examples_for 'deferred execution' do
    before do
      deferred_execution
    end

    it 'creates outer span without a parent' do
      expect(outer_span).to be_root_span
    end

    it 'writes inner span to tracer' do
      expect(spans).to include(inner_span)
    end

    it 'writes outer span to tracer' do
      expect(spans).to include(outer_span)
    end
  end

  describe 'patching' do
    subject(:patch) do
      Datadog.configure do |c|
        c.tracing.instrument :concurrent_ruby
      end
    end

    it 'adds FuturePatch to Future ancestors' do
      expect { patch }.to change { ::Concurrent::Future.ancestors.map(&:to_s) }
        .to include('Datadog::Tracing::Contrib::ConcurrentRuby::FuturePatch')
    end
  end

  context 'when context propagation is disabled' do
    it_behaves_like 'deferred execution'

    it 'inner span should not have parent' do
      deferred_execution
      expect(inner_span).to be_root_span
    end
  end

  context 'when context propagation is enabled' do
    before do
      Datadog.configure do |c|
        c.tracing.instrument :concurrent_ruby
      end
    end

    it_behaves_like 'deferred execution'

    it 'inner span parent should be included in outer span' do
      deferred_execution
      expect(inner_span.parent_id).to eq(outer_span.span_id)
    end
  end
end
