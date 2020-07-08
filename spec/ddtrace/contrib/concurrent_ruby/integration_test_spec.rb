require 'concurrent/future'

require 'ddtrace/contrib/support/spec_helper'
require 'ddtrace'

RSpec.describe 'ConcurrentRuby integration tests' do
  # DEV We save an unmodified copy of Concurrent::Future.
  let!(:unmodified_future) { ::Concurrent::Future.dup }

  # DEV We then restore Concurrent::Future, a dangerous game.
  after do
    ::Concurrent.send(:remove_const, :Future)
    ::Concurrent.const_set('Future', unmodified_future)
    remove_patch!(:concurrent_ruby)
  end

  let(:configuration_options) { {} }

  subject(:deferred_execution) do
    outer_span = tracer.trace('outer_span')
    future = Concurrent::Future.new do
      tracer.trace('inner_span') {}
    end
    future.execute

    future.wait
    outer_span.finish
  end

  let(:outer_span) { spans.find { |s| s.name == 'outer_span' } }
  let(:inner_span) { spans.find { |s| s.name == 'inner_span' } }

  shared_examples_for 'deferred execution' do
    before do
      deferred_execution
    end

    it 'creates outer span with nil parent' do
      expect(outer_span.parent).to be_nil
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
        c.use :concurrent_ruby
      end
    end

    it 'should add FuturePatch to Future ancestors' do
      expect { patch }.to change { ::Concurrent::Future.ancestors.map(&:to_s) }
        .to include('Datadog::Contrib::ConcurrentRuby::FuturePatch')
    end
  end

  context 'when context propagation is disabled' do
    it_should_behave_like 'deferred execution'

    it 'inner span should not have parent' do
      deferred_execution
      expect(inner_span.parent).to be_nil
    end
  end

  context 'when context propagation is enabled' do
    before do
      Datadog.configure do |c|
        c.use :concurrent_ruby
      end
    end

    it_should_behave_like 'deferred execution'

    it 'inner span parent should be included in outer span' do
      deferred_execution
      expect(inner_span.parent).to eq(outer_span)
    end
  end
end
