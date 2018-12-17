require 'concurrent/future'

require 'spec_helper'
require 'ddtrace'

RSpec.describe Datadog::Contrib::ConcurrentRuby::Integration do
  around do |example|
    unmodified_future = ::Concurrent::Future.dup
    example.run
    ::Concurrent.send(:remove_const, :Future)
    ::Concurrent.const_set('Future', unmodified_future)
    remove_patch!(:concurrent_ruby)
  end

  let(:tracer) { ::Datadog::Tracer.new(writer: FauxWriter.new) }
  let(:configuration_options) { { tracer: tracer } }

  subject(:deferred_execution) do
    outer_span = tracer.trace('outer_span')
    inner_span = nil
    future = Concurrent::Future.new do
      inner_span = tracer.trace('inner_span')
      inner_span.finish
    end
    future.execute

    future.wait
    outer_span.finish

    { outer_span: outer_span, inner_span: inner_span }
  end

  let(:outer_span) { deferred_execution[:outer_span] }
  let(:inner_span) { deferred_execution[:inner_span] }

  shared_examples_for 'deferred execution' do
    before do
      deferred_execution
    end

    it 'creates outer span with nil parent' do
      expect(outer_span.parent).to be_nil
    end

    it 'writes inner span to tracer' do
      expect(tracer.writer.spans).to include(inner_span)
    end

    it 'writes outer span to tracer' do
      expect(tracer.writer.spans).to include(outer_span)
    end
  end

  describe 'patching' do
    subject(:patch) do
      Datadog.configure do |c|
        c.use :concurrent_ruby, tracer: tracer
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
      expect(inner_span.parent).to be_nil
    end
  end

  context 'when context propagation is enabled' do
    it_should_behave_like 'deferred execution'

    before do
      Datadog.configure do |c|
        c.use :concurrent_ruby, tracer: tracer
      end
    end

    it 'inner span parent should be included in outer span' do
      expect(inner_span.parent).to eq(outer_span)
    end
  end
end
