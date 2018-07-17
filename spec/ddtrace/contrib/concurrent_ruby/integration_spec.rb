require 'concurrent/future'

require 'spec_helper'
require 'ddtrace'

RSpec.describe Datadog::Contrib::ConcurrentRuby::Integration do
  let(:tracer) { ::Datadog::Tracer.new(writer: FauxWriter.new) }
  let(:configuration_options) { { tracer: tracer } }

  around do |example|
    unmodified = ::Concurrent::Future.dup
    Datadog.registry[:concurrent_ruby].patcher.instance_variable_set(:@done_once, {})
    example.run
    ::Concurrent.send(:remove_const, :Future)
    ::Concurrent.const_set('Future', unmodified)
  end

  subject(:deferred_execution) do
    outer_span = tracer.trace('outer_span')
    inner_span = nil
    future = Concurrent::Future.execute do
      inner_span = tracer.trace('inner_span')
      inner_span.finish
    end

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
      expect { patch }.to change { ::Concurrent::Future.ancestors }
        .to include(Datadog::Contrib::ConcurrentRuby::FuturePatch)
    end

    it 'should add datadog_configuration method to Future instance' do
      expect { patch }.to change { ::Concurrent::Future.new {} }.to respond_to(:datadog_configuration)
    end
  end

  context 'when context propagation is disabled' do
    it_should_behave_like 'deferred execution'

    it 'inner span should not have parent' do
      expect(inner_span.parent).to be_nil
    end

    it 'Future should not have patching ancestors' do
      expect(::Concurrent::Future.ancestors).not_to include(Datadog::Contrib::ConcurrentRuby::FuturePatch)
    end
  end

  context 'when context propagation is enabled' do
    it_should_behave_like 'deferred execution'

    before do
      Datadog.configure do |c|
        c.use :concurrent_ruby, tracer: tracer
      end
    end

    it 'Concurrent::Future should have patching ancestors' do
      expect(::Concurrent::Future.ancestors).to include(Datadog::Contrib::ConcurrentRuby::FuturePatch)
    end

    it 'inner span parent should be included in outer span' do
      expect(inner_span.parent).to eq(outer_span)
    end
  end
end
