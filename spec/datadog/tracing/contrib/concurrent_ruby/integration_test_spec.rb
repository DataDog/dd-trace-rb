require 'concurrent-ruby' # concurrent-ruby is not modular

require 'datadog/tracing/contrib/support/spec_helper'
require 'ddtrace'
require 'spec/support/thread_helpers'

RSpec.describe 'ConcurrentRuby integration tests' do
  let(:configuration_options) { {} }
  let(:outer_span) { spans.find { |s| s.name == 'outer_span' } }
  let(:inner_span) { spans.find { |s| s.name == 'inner_span' } }

  before do
    # stub inheritance chain for instrumentation rollback
    stub_const('Concurrent::Async::AsyncDelegator', ::Concurrent::Async.const_get(:AsyncDelegator).dup)
    stub_const('Concurrent::Promises', ::Concurrent::Promises.dup)
    stub_const('Concurrent::Future', ::Concurrent::Future.dup)
  end

  after do
    remove_patch!(:concurrent_ruby)
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

  context 'Concurrent::Promises::Future' do
    before(:context) do
      # Execute an async future to force the eager creation of internal
      # global threads that are never closed.
      #
      # This allows us to separate internal concurrent-ruby threads
      # from ddtrace threads for leak detection. We need to create the maximum
      # number of threads that will be created concurrently in a test, which in
      # this case is 2.
      ThreadHelpers.with_leaky_thread_creation(:concurrent_ruby) do
        Concurrent::Promises.future do
          Concurrent::Promises.future {}.value
        end.value
      end
    end

    subject(:deferred_execution) do
      outer_span = tracer.trace('outer_span')
      future = Concurrent::Promises.future do
        tracer.trace('inner_span') {}
      end

      future.wait
      outer_span.finish
    end

    describe 'patching' do
      subject(:patch) do
        Datadog.configure do |c|
          c.tracing.instrument :concurrent_ruby
        end
      end

      it 'adds PromisesFuturePatch to Promises ancestors' do
        expect { patch }.to change { ::Concurrent::Promises.singleton_class.ancestors.map(&:to_s) }
          .to include('Datadog::Tracing::Contrib::ConcurrentRuby::PromisesFuturePatch')
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
        expect(inner_span.parent_id).to eq(outer_span.id)
      end

      context 'when there are multiple futures with inner spans that have the same parent' do
        let(:second_inner_span) { spans.find { |s| s.name == 'second_inner_span' } }

        subject(:multiple_deferred_executions) do
          # use a barrier to ensure both threads are created before continuing
          barrier = Concurrent::CyclicBarrier.new(2)

          outer_span = tracer.trace('outer_span')
          future_1 = Concurrent::Promises.future do
            barrier.wait
            tracer.trace('inner_span') do
              barrier.wait
            end
          end

          future_2 = Concurrent::Promises.future do
            barrier.wait
            tracer.trace('second_inner_span') do
              barrier.wait
            end
          end

          future_1.wait
          future_2.wait
          outer_span.finish
        end

        describe 'it correctly associates to the parent span' do
          it 'both inner span parents should be included in same outer span' do
            multiple_deferred_executions

            expect(inner_span.parent_id).to eq(outer_span.id)
            expect(second_inner_span.parent_id).to eq(outer_span.id)
          end
        end
      end

      context 'when propagates without an active trace' do
        it 'creates a root span' do
          future = Concurrent::Promises.future do
            tracer.trace('inner_span') {}
          end

          future.wait

          expect(inner_span).to be_root_span
        end
      end
    end
  end

  context 'Concurrent::Future (deprecated)' do
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

    subject(:deferred_execution) do
      outer_span = tracer.trace('outer_span')
      future = Concurrent::Future.new do
        tracer.trace('inner_span') {}
      end
      future.execute

      future.wait
      outer_span.finish
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
        expect(inner_span.parent_id).to eq(outer_span.id)
      end
    end
  end

  context 'Concurrent::Async' do
    before(:context) do
      # Execute an async future to force the eager creation of internal
      # global threads that are never closed.
      #
      # This allows us to separate internal concurrent-ruby threads
      # from ddtrace threads for leak detection. We need to create the maximum
      # number of threads that will be created concurrently in a test, which in
      # this case is 2.
      ThreadHelpers.with_leaky_thread_creation(:concurrent_ruby) do
        klass = Class.new do
          include Concurrent::Async
          def echo
            yield if block_given?
          end
        end
        klass.new.async.echo { klass.new.async.echo.value }.value
      end
    end

    let(:async_klass) do
      Class.new do
        include Concurrent::Async
        def echo
          yield if block_given?
        end
      end
    end

    subject(:deferred_execution) do
      outer_span = tracer.trace('outer_span')

      ivar = async_klass.new.async.echo do
        tracer.trace('inner_span') {}
      end
      ivar.value

      outer_span.finish
    end

    describe 'patching' do
      subject(:patch) do
        Datadog.configure do |c|
          c.tracing.instrument :concurrent_ruby
        end
      end

      it 'adds PromisesFuturePatch to Promises ancestors' do
        expect { patch }.to change { ::Concurrent::Promises.singleton_class.ancestors.map(&:to_s) }
          .to include('Datadog::Tracing::Contrib::ConcurrentRuby::PromisesFuturePatch')
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
        expect(inner_span.parent_id).to eq(outer_span.id)
      end

      context 'when there are multiple asyncs with inner spans that have the same parent' do
        let(:second_inner_span) { spans.find { |s| s.name == 'second_inner_span' } }

        subject(:multiple_deferred_executions) do
          # use a barrier to ensure both threads are created before continuing
          barrier = Concurrent::CyclicBarrier.new(2)

          outer_span = tracer.trace('outer_span')

          ivar_1 = async_klass.new.async.echo do
            barrier.wait
            tracer.trace('inner_span') do
              barrier.wait
            end
          end

          ivar_2 = async_klass.new.async.echo do
            barrier.wait
            tracer.trace('second_inner_span') do
              barrier.wait
            end
          end

          ivar_1.wait
          ivar_2.wait
          outer_span.finish
        end

        describe 'it correctly associates to the parent span' do
          it 'both inner span parents should be included in same outer span' do
            multiple_deferred_executions

            expect(inner_span.parent_id).to eq(outer_span.id)
            expect(second_inner_span.parent_id).to eq(outer_span.id)
          end
        end
      end

      context 'when propagates without an active trace' do
        it 'creates a root span' do
          async_klass.new.async.echo do
            tracer.trace('inner_span') {}
          end.value

          expect(inner_span).to be_root_span
        end
      end
    end
  end
end
