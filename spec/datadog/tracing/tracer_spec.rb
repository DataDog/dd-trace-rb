require 'spec_helper'

require 'time'

require 'datadog/core'
require 'datadog/core/environment/identity'
require 'datadog/core/environment/socket'

require 'datadog/tracing'
require 'datadog/tracing/context'
require 'datadog/tracing/correlation'
require 'datadog/tracing/flush'
require 'datadog/tracing/sampling/ext'
require 'datadog/tracing/span_operation'
require 'datadog/tracing/trace_operation'
require 'datadog/tracing/tracer'
require 'datadog/tracing/utils'
require 'datadog/tracing/writer'

RSpec.describe Datadog::Tracing::Tracer do
  let(:writer) { FauxWriter.new }
  let(:tracer_options) { {} }

  subject(:tracer) { described_class.new(writer: writer, **tracer_options) }

  after { tracer.shutdown! }

  describe '::new' do
    context 'given :trace_flush' do
      let(:tracer_options) { super().merge(trace_flush: trace_flush) }
      let(:trace_flush) { instance_double(Datadog::Tracing::Flush::Finished) }
      it { is_expected.to have_attributes(trace_flush: trace_flush) }
    end
  end

  describe '#tags' do
    subject(:tags) { tracer.tags }

    let(:env_tags) { {} }

    before { allow(Datadog.configuration).to receive(:tags).and_return(env_tags) }

    context 'by default' do
      it { is_expected.to eq env_tags }
    end

    context 'when equivalent String and Symbols are added' do
      shared_examples 'equivalent tags' do
        it 'retains the tag only as a String' do
          is_expected.to include('host')
          is_expected.to_not include(:host)
        end

        it 'retains only the last value' do
          is_expected.to include('host' => 'b')
        end
      end

      context 'with #set_tags' do
        it_behaves_like 'equivalent tags' do
          before do
            tracer.set_tags('host' => 'a')
            tracer.set_tags(host: 'b')
          end
        end

        it_behaves_like 'equivalent tags' do
          before do
            tracer.set_tags(host: 'a')
            tracer.set_tags('host' => 'b')
          end
        end

        context 'with multiple tags' do
          it 'sets all tags' do
            tracer.set_tags(host: 'h1', custom_tag: 'my-tag')

            is_expected.to include('host' => 'h1')
            is_expected.to include('custom_tag' => 'my-tag')
          end
        end
      end
    end
  end

  describe '#trace' do
    let(:name) { 'span.name' }
    let(:options) { {} }

    shared_examples 'shared #trace behavior' do
      context 'with options to be forwarded to the span' do
        context 'service:' do
          let(:options) { { service: service } }
          let(:service) { 'my-service' }

          it 'sets the span service' do
            expect(span.service).to eq(service)
          end
        end

        context 'resource:' do
          let(:options) { { resource: resource } }
          let(:resource) { 'my-resource' }

          it 'sets the span resource' do
            expect(span.resource).to eq(resource)
          end
        end

        context 'span_type:' do
          let(:options) { { span_type: span_type } }
          let(:span_type) { 'my-span_type' }

          it 'sets the span resource' do
            expect(span.span_type).to eq(span_type)
          end
        end

        context 'tags:' do
          let(:options) { { tags: tags } }
          let(:tags) { { tag_name => tag_value } }
          let(:tag_name) { 'my' }
          let(:tag_value) { 'tag' }

          it 'sets the span tags' do
            expect(span.get_tag('my')).to eq('tag')
          end

          context 'and default tags are set on the tracer' do
            let(:tracer_options) { { tags: default_tags } }

            let(:default_tags) { { default_tag_name => default_tag_value } }
            let(:default_tag_name) { 'default_tag' }
            let(:default_tag_value) { 'default_value' }

            it 'includes both :tags and default tags' do
              expect(span.get_tag(default_tag_name)).to eq(default_tag_value)
              expect(span.get_tag(tag_name)).to eq(tag_value)
            end

            context 'which conflicts with :tags' do
              let(:tag_name) { default_tag_name }

              it 'uses the tag from :tags' do
                expect(span.get_tag(tag_name)).to eq(tag_value)
              end
            end
          end
        end
      end
    end

    context 'given a block' do
      subject(:trace) { tracer.trace(name, **options, &block) }

      let(:block) { proc { result } }
      let(:result) { double('result') }

      it_behaves_like 'shared #trace behavior' do
        before { trace }

        context 'start_time:' do
          let(:options) { { start_time: start_time } }
          let(:start_time) { Time.utc(2021, 8, 3) }

          it 'is ignored' do
            expect(span.start_time).to_not eq(start_time)
          end
        end
      end

      context 'when starting a span' do
        it 'yields span provided block' do
          expect { |b| tracer.trace(name, &b) }.to yield_with_args(
            a_kind_of(Datadog::Tracing::SpanOperation),
            a_kind_of(Datadog::Tracing::TraceOperation)
          )
        end

        it 'returns block result' do
          expect(trace).to eq(result)
        end

        it 'sets the span name from the name argument' do
          trace
          expect(span.name).to eq(name)
        end

        context 'with diagnostics debug enabled' do
          include_context 'tracer logging'

          before do
            Datadog.configure do |c|
              c.diagnostics.debug = true
            end

            allow(writer).to receive(:write)
            allow(Datadog.logger).to receive(:debug)
          end

          it 'records span flushing to logger' do
            trace
            expect(Datadog.logger).to have_lazy_debug_logged('Writing 1 span')
            expect(Datadog.logger).to have_lazy_debug_logged('Name: span.name')
          end
        end

        it 'adds a runtime ID to the trace' do
          tracer.trace(name) do
            # Do something
          end

          expect(traces.first.runtime_id).to eq(Datadog::Core::Environment::Identity.id)
        end

        context 'when #report_hostname' do
          context 'is enabled' do
            before do
              allow(Datadog.configuration.tracing).to receive(:report_hostname).and_return(true)
            end

            it 'adds a hostname to the trace' do
              tracer.trace(name) do |_span, trace|
                expect(trace.hostname).to eq(Datadog::Core::Environment::Socket.hostname)
              end
            end
          end

          context 'is disabled' do
            before { allow(Datadog.configuration.tracing).to receive(:report_hostname).and_return(false) }

            it 'adds a hostname to the trace' do
              tracer.trace(name) do |_span, trace|
                expect(trace.hostname).to be nil
              end
            end
          end
        end
      end

      context 'when nesting spans' do
        it 'propagates parent span and uses default service name' do
          tracer.trace('parent', service: 'service-parent') do
            tracer.trace('child1') { |s| s.set_tag('tag', 'tag_1') }
            tracer.trace('child2', service: 'service-child2') { |s| s.set_tag('tag', 'tag_2') }
          end

          expect(spans).to have(3).items

          child1, child2, parent = spans # Spans are sorted alphabetically by operation name

          expect(parent).to be_root_span
          expect(parent.name).to eq('parent')
          expect(parent.service).to eq('service-parent')

          expect(child1.parent_id).to be(parent.span_id)
          expect(child1.name).to eq('child1')
          expect(child1.service).to eq(tracer.default_service)
          expect(child1.get_tag('tag')).to eq('tag_1')

          expect(child2.parent_id).to be(parent.span_id)
          expect(child2.name).to eq('child2')
          expect(child2.service).to eq('service-child2')
          expect(child2.get_tag('tag')).to eq('tag_2')
        end

        it 'trace has a runtime ID and PID tags' do
          tracer.trace(name) do
            # Do nothing
          end

          expect(traces.first.runtime_id).to eq(Datadog::Core::Environment::Identity.id)
          expect(traces.first.process_id).to eq(Process.pid)
        end

        context 'with spans that finish out of order' do
          context 'within a trace' do
            subject!(:trace) do
              tracer.trace('grandparent') do
                child, grandchild = nil

                tracer.trace('parent') do
                  child = tracer.trace('child')
                  grandchild = tracer.trace('grandchild')
                end

                child.finish
                grandchild.finish

                tracer.trace('uncle') do
                  tracer.trace('nephew').finish
                end
              end
            end

            it 'has correct relationships' do
              grandparent = spans.find { |s| s.name == 'grandparent' }
              parent = spans.find { |s| s.name == 'parent' }
              child = spans.find { |s| s.name == 'child' }
              grandchild = spans.find { |s| s.name == 'grandchild' }
              uncle = spans.find { |s| s.name == 'uncle' }
              nephew = spans.find { |s| s.name == 'nephew' }

              expect(spans.all? { |s| s.trace_id == grandparent.trace_id }).to be true

              expect(grandparent).to be_root_span
              expect(parent.parent_id).to be grandparent.span_id
              expect(child.parent_id).to be parent.span_id
              expect(grandchild.parent_id).to be child.span_id
              expect(uncle.parent_id).to be grandparent.span_id
              expect(nephew.parent_id).to be uncle.span_id
            end
          end

          context 'across traces' do
            subject!(:trace) do
              child, grandchild = nil
              tracer.trace('grandparent') do
                tracer.trace('parent') do
                  child = tracer.trace('child')
                  grandchild = tracer.trace('grandchild')
                end
              end

              tracer.trace('great uncle') do
                tracer.trace('second cousin').finish
              end

              child.finish
              grandchild.finish
            end

            it 'has correct relationships' do
              grandparent = spans.find { |s| s.name == 'grandparent' }
              parent = spans.find { |s| s.name == 'parent' }
              child = spans.find { |s| s.name == 'child' }
              grandchild = spans.find { |s| s.name == 'grandchild' }
              great_uncle = spans.find { |s| s.name == 'great uncle' }
              second_cousin = spans.find { |s| s.name == 'second cousin' }

              expect(
                [
                  grandparent,
                  parent,
                  child,
                  grandchild
                ].all? { |s| s.trace_id == grandparent.trace_id }
              ).to be true
              expect(grandparent.parent_id).to eq(0)
              expect(parent.parent_id).to eq(grandparent.id)
              expect(child.parent_id).to eq(parent.id)
              expect(grandchild.parent_id).to eq(child.id)

              expect(
                [
                  great_uncle,
                  second_cousin
                ].all? { |s| s.trace_id == great_uncle.trace_id }
              ).to be true
              expect(great_uncle.parent_id).to eq(0)
              expect(second_cousin.parent_id).to eq(great_uncle.id)

              # Should be separate traces (can't have two root spans for a trace)
              expect(grandparent.trace_id).to_not eq(great_uncle.trace_id)
            end
          end
        end

        context 'with forking' do
          before { skip 'Fork not supported on current platform' unless Process.respond_to?(:fork) }

          it 'the trace has a runtime ID tag' do
            tracer.trace(name) do |_parent_span, trace|
              parent_process_id = Datadog::Core::Environment::Identity.id
              expect(trace.flush!.runtime_id).to eq(parent_process_id)

              tracer.trace(name) do |_child_span|
                expect_in_fork do
                  fork_process_id = Datadog::Core::Environment::Identity.id
                  expect(fork_process_id).to_not eq(parent_process_id)

                  tracer.trace(name) do |_fork_parent_span, fork_trace|
                    # Tag should be set on the fork's parent span, but not be the same as the parent process runtime ID
                    expect(fork_trace.flush!.runtime_id).to eq(fork_process_id)
                    expect(fork_trace.flush!.runtime_id).to_not eq(parent_process_id)
                  end
                end
              end
            end
          end
        end
      end

      context 'when building a span fails' do
        before do
          allow(tracer).to receive(:start_trace).and_raise(error)
        end

        let(:error) { error_class.new }
        let(:error_class) { Class.new(StandardError) }

        it 'still yields to the block and does not raise an error' do
          expect do
            expect do |b|
              tracer.trace(name, &b)
            end.to yield_with_args(
              a_kind_of(Datadog::Tracing::SpanOperation),
              a_kind_of(Datadog::Tracing::TraceOperation)
            )
          end.to_not raise_error
        end

        context 'with fatal exception' do
          let(:fatal_error) { stub_const('FatalError', Class.new(Exception)) } # rubocop:disable Lint/InheritException

          before do
            # Raise error at first line of begin block
            allow(tracer).to receive(:start_trace).and_raise(fatal_error)
          end

          it 'does not yield to block and reraises exception' do
            expect do |b|
              expect do
                tracer.trace(name, &b)
              end.to raise_error(fatal_error)
            end.to_not yield_control
          end
        end
      end

      context 'when the block raises an error' do
        let(:block) { proc { raise error } }
        let(:error) { error_class.new('error message') }
        let(:error_class) { stub_const('TestError', Class.new(StandardError)) }

        it 'sets span error status and information' do
          expect { trace }.to raise_error(error)

          expect(span).to have_error
          expect(span).to have_error_type('TestError')
          expect(span).to have_error_message('error message')
          expect(span).to have_error_stack(include('tracer_spec.rb'))
        end

        context 'that is not a StandardError' do
          let(:error_class) { stub_const('CriticalError', Class.new(Exception)) } # rubocop:disable Lint/InheritException

          it 'traces non-StandardError and re-raises it' do
            expect { trace }.to raise_error(error)

            expect(span).to have_error
            expect(span).to have_error_type('CriticalError')
            expect(span).to have_error_message('error message')
            expect(span).to have_error_stack(include('tracer_spec.rb'))
          end
        end

        context 'and the on_error option' do
          context 'is not provided' do
            it 'propagates the error' do
              expect_any_instance_of(Datadog::Tracing::SpanOperation).to receive(:set_error)
                .with(error)
              expect { trace }.to raise_error(error)
            end
          end

          context 'is a block' do
            it 'yields to the error block and raises the error' do
              expect do
                expect do |b|
                  tracer.trace(name, on_error: b.to_proc, &block)
                end.to yield_with_args(
                  a_kind_of(Datadog::Tracing::SpanOperation),
                  error
                )
              end.to raise_error(error)

              expect(span).to_not have_error
            end
          end

          context 'is a block that raises its own error' do
            let(:error_raising_block) { proc { raise 'I also raise an error.' } }
            let(:log_spy) { spy(Datadog::Core::Logger) }

            before { allow(Datadog).to receive(:logger).and_return(log_spy) }

            it 'fallbacks to default error handler and log a debug message' do
              allow(Datadog.logger).to receive(:debug)

              expect do
                tracer.trace(name, on_error: error_raising_block, &block)
              end.to raise_error(error)

              expect(Datadog.logger).to have_lazy_debug_logged('Custom on_error handler')
              expect(Datadog.logger).to have_lazy_debug_logged('span_operation.rb') # Proc declaration location
            end
          end

          context 'is a block that is not a Proc' do
            let(:not_a_proc_block) { 'not a proc' }

            it 'fallbacks to default error handler and log a debug message' do
              expect do
                tracer.trace(name, on_error: not_a_proc_block, &block)
              end.to raise_error(error)
            end
          end
        end
      end

      context 'for span sampling' do
        let(:tracer_options) { super().merge(span_sampler: span_sampler) }
        let(:span_sampler) { instance_double(Datadog::Tracing::Sampling::Span::Sampler) }
        let(:block) do
          proc do |span_op, trace_op|
            @span_op = span_op
            @trace_op = trace_op
          end
        end

        before do
          allow(span_sampler).to receive(:sample!)
        end

        it 'invokes the span sampler with the current span and trace operation' do
          trace
          expect(span_sampler).to have_received(:sample!).with(@trace_op, @span_op.finish)
        end
      end
    end

    context 'without a block' do
      subject(:trace) { tracer.trace(name, **options) }

      it_behaves_like 'shared #trace behavior' do
        let(:span) { trace }

        context 'start_time:' do
          let(:options) { { start_time: start_time } }
          let(:start_time) { Time.utc(2021, 8, 3) }

          it 'sets the span start_time' do
            expect(span.start_time).to eq(start_time)
          end
        end
      end

      context 'with _context: option' do
        let(:options) { { _context: context_value } }

        context 'as a context' do
          let(:context) { Datadog::Tracing::Context.new }
          let(:context_value) { context }

          it 'creates an unmanaged trace' do
            tracer.trace 'another' do
              expect(trace).to be_root_span
              # This context is one-off, and isn't stored in
              # the tracer at all. We can only see the span
              # isn't tracked by the tracer.
              expect(trace).to_not be(tracer.active_span)
            end
          end
        end
      end

      context 'without context: option' do
        let(:options) { {} }

        it 'creates span with current context' do
          tracer.trace 'root' do |_root_span|
            tracer.trace 'another' do |another_span|
              expect(trace.send(:parent)).to eq another_span
            end
          end
        end
      end

      context 'with child finishing after parent' do
        it "allows child span to exceed parent's end time" do
          parent = tracer.trace('parent')
          child = tracer.trace('child')

          parent.finish
          sleep(0.001)
          child.finish

          expect(parent).to be_root_span
          expect(child.send(:parent)).to be(parent)
          expect(child.end_time).to be > parent.end_time
        end
      end

      context 'for span sampling' do
        let(:tracer_options) { super().merge(span_sampler: span_sampler) }
        let(:span_sampler) { instance_double(Datadog::Tracing::Sampling::Span::Sampler) }

        before do
          allow(span_sampler).to receive(:sample!)
        end

        it 'invokes the span sampler with the current span and trace operation' do
          span_op = trace
          trace_op = tracer.active_trace
          span = span_op.finish

          expect(span_sampler).to have_received(:sample!).with(trace_op, span)
        end
      end
    end
  end

  describe '#call_context' do
    subject(:call_context) { tracer.send(:call_context) }

    let(:context) { instance_double(Datadog::Tracing::Context) }

    context 'given no arguments' do
      it 'returns the currently active, default context' do
        expect(tracer.provider)
          .to receive(:context)
          .with(nil)
          .and_return(context)

        is_expected.to be context
      end
    end

    context 'given a key' do
      subject(:call_context) { tracer.send(:call_context, key) }

      let(:key) { Thread.current }

      it 'returns the context associated with the key' do
        expect(tracer.provider)
          .to receive(:context)
          .with(key)
          .and_return(context)

        is_expected.to be context
      end
    end
  end

  describe '#active_trace' do
    let(:trace) { instance_double(Datadog::Tracing::TraceOperation) }
    let(:call_context) { instance_double(Datadog::Tracing::Context, active_trace: trace) }

    before do
      expect(tracer)
        .to receive(:call_context)
        .with(key)
        .and_return(call_context)
    end

    context 'given no arguments' do
      subject(:active_trace) { tracer.active_trace }
      let(:key) { nil }

      it 'returns the currently active, default active span' do
        is_expected.to be(trace)
      end
    end

    context 'given a key' do
      subject(:active_trace) { tracer.active_trace(key) }
      let(:key) { double('key') }

      it 'returns the active span associated with the key' do
        is_expected.to be(trace)
      end
    end
  end

  describe '#active_span' do
    let(:span) { instance_double(Datadog::Tracing::SpanOperation) }
    let(:trace) { instance_double(Datadog::Tracing::TraceOperation, active_span: span) }
    let(:call_context) { instance_double(Datadog::Tracing::Context, active_trace: trace) }

    before do
      expect(tracer)
        .to receive(:call_context)
        .with(key)
        .and_return(call_context)
    end

    context 'given no arguments' do
      subject(:active_span) { tracer.active_span }
      let(:key) { nil }

      it 'returns the currently active, default active span' do
        is_expected.to be(span)
      end
    end

    context 'given a key' do
      subject(:active_span) { tracer.active_span(key) }
      let(:key) { double('key') }

      it 'returns the active span associated with the key' do
        is_expected.to be(span)
      end
    end
  end

  describe '#active_correlation' do
    subject(:active_correlation) { tracer.active_correlation }

    context 'when a trace is active' do
      let(:span) { @span }

      around do |example|
        tracer.trace('test') do |span|
          @span = span
          example.run
        end
      end

      it 'produces an Identifier with data' do
        is_expected.to be_a_kind_of(Datadog::Tracing::Correlation::Identifier)
        expect(active_correlation.trace_id).to eq(span.trace_id)
        expect(active_correlation.span_id).to eq(span.span_id)
      end
    end

    context 'when no trace is active' do
      it 'produces an empty Identifier' do
        is_expected.to be_a_kind_of(Datadog::Tracing::Correlation::Identifier)
        expect(active_correlation.trace_id).to eq 0
        expect(active_correlation.span_id).to eq 0
      end
    end

    context 'given a key' do
      subject(:active_correlation) { tracer.active_correlation(key) }

      let(:key) { Thread.current }
      let(:call_context) { instance_double(Datadog::Tracing::Context) }

      it 'returns a correlation that matches that context' do
        expect(tracer)
          .to receive(:call_context)
          .with(key)
          .and_call_original

        is_expected.to be_a_kind_of(Datadog::Tracing::Correlation::Identifier)
      end
    end
  end

  describe '#continue_trace!' do
    subject(:continue_trace!) { tracer.continue_trace!(digest) }

    context 'given nil' do
      let(:digest) { nil }

      before { continue_trace! }

      it 'starts a new trace' do
        tracer.trace('operation') do |span, trace|
          expect(trace).to have_attributes(
            origin: nil,
            sampling_priority: 1
          )

          expect(span).to have_attributes(
            parent_id: 0,
            span_id: a_kind_of(Integer),
            trace_id: a_kind_of(Integer)
          )
        end

        expect(tracer.active_trace).to be nil
      end

      context 'and a block' do
        it do
          expect { |b| tracer.continue_trace!(digest, &b) }
            .to yield_control
        end

        it 'restores the original active trace afterwards' do
          tracer.continue_trace!(digest)
          original_trace = tracer.active_trace
          expect(original_trace).to be_a_kind_of(Datadog::Tracing::TraceOperation)

          tracer.continue_trace!(digest) do
            expect(tracer.active_trace).to be_a_kind_of(Datadog::Tracing::TraceOperation)
            expect(tracer.active_trace).to_not be original_trace
          end

          expect(tracer.active_trace).to be original_trace
        end
      end
    end

    context 'given a TraceDigest' do
      let(:digest) do
        Datadog::Tracing::TraceDigest.new(
          span_id: Datadog::Tracing::Utils.next_id,
          trace_distributed_tags: { '_dd.p.test' => 'value' },
          trace_id: Datadog::Tracing::Utils.next_id,
          trace_origin: 'synthetics',
          trace_sampling_priority: Datadog::Tracing::Sampling::Ext::Priority::USER_KEEP,
        )
      end

      before { continue_trace! }

      it 'causes next #trace to continue the trace' do
        tracer.trace('operation') do |span, trace|
          expect(trace).to have_attributes(
            origin: digest.trace_origin,
            sampling_priority: digest.trace_sampling_priority,
          )

          expect(trace.send(:distributed_tags)).to eq('_dd.p.test' => 'value')

          expect(span).to have_attributes(
            parent_id: digest.span_id,
            trace_id: digest.trace_id
          )
        end

        expect(tracer.active_trace).to be nil
      end

      it 'is consumed by the next trace and isn\'t reused' do
        tracer.trace('first') do |span, trace|
          # Should consume the continuation
        end

        expect(tracer.active_trace).to be nil

        tracer.trace('second') do |span, trace|
          expect(trace).to have_attributes(
            origin: nil,
            sampling_priority: 1
          )

          expect(span.trace_id).to_not eq(digest.trace_id)
          expect(span.parent_id).to eq(0)
        end

        expect(tracer.active_trace).to be nil
      end

      context 'and a block' do
        it do
          expect { |b| tracer.continue_trace!(digest, &b) }
            .to yield_control
        end

        it 'restores the original active trace afterwards' do
          tracer.continue_trace!(digest)
          original_trace = tracer.active_trace
          expect(original_trace).to be_a_kind_of(Datadog::Tracing::TraceOperation)

          tracer.continue_trace!(digest) do
            expect(tracer.active_trace).to be_a_kind_of(Datadog::Tracing::TraceOperation)
            expect(tracer.active_trace).to_not be original_trace
          end

          expect(tracer.active_trace).to be original_trace
        end
      end
    end

    context 'given a TraceOperation' do
      let(:digest) { Datadog::Tracing::TraceOperation.new }

      before { continue_trace! }

      it 'starts a new trace' do
        tracer.trace('operation') do |span, trace|
          expect(trace).to have_attributes(
            origin: nil,
            sampling_priority: 1
          )

          expect(span).to have_attributes(
            parent_id: 0,
            span_id: a_kind_of(Integer),
            trace_id: a_kind_of(Integer)
          )
        end
      end
    end
  end

  describe '#trace_completed' do
    subject(:trace_completed) { tracer.trace_completed }
    it { is_expected.to be_a_kind_of(described_class::TraceCompleted) }
  end

  describe '#default_service' do
    subject(:default_service) { tracer.default_service }

    context 'when tracer is initialized with a default_service' do
      let(:tracer_options) { { **super(), default_service: default_service_value } }
      let(:default_service_value) { 'test_default_service' }

      it { is_expected.to be default_service_value }
    end

    context 'when no default_service is provided' do
      it 'sets the default_service based on the current ruby process name' do
        is_expected.to include 'rspec'
      end
    end
  end

  describe '#enabled' do
    subject(:enabled) { tracer.enabled }

    it 'is enabled by default' do
      is_expected.to be(true)
    end
  end

  describe '#enabled=' do
    subject(:set_enabled) { tracer.enabled = enabled? }

    before { set_enabled }

    context 'with the tracer enabled' do
      let(:enabled?) { true }

      it 'generates traces' do
        tracer.trace('test') {}

        expect(spans).to have(1).item
      end
    end

    context 'with the tracer disabled' do
      let(:enabled?) { false }

      it 'does not generate traces' do
        tracer.trace('test') {}

        expect(spans).to be_empty
      end
    end
  end

  describe '#shutdown!' do
    subject(:shutdown!) { tracer.shutdown! }
    let(:writer) { instance_double(Datadog::Tracing::Writer) }

    context 'when the tracer is enabled' do
      let(:tracer_options) { { enabled: true } }

      context 'when writer is nil' do
        let(:writer) { nil }

        it do
          expect(writer).to_not receive(:stop)
          shutdown!
        end
      end

      context 'when writer is not nil' do
        it do
          # Because test cleanup does #shutdown!
          expect(writer).to receive(:stop).at_least(:once)
          shutdown!
        end
      end
    end

    context 'when the tracer is disabled' do
      let(:tracer_options) { { enabled: false } }

      it do
        expect(writer).to_not receive(:stop)
        shutdown!
      end
    end
  end
end

RSpec.describe Datadog::Tracing::Tracer::TraceCompleted do
  subject(:event) { described_class.new }

  describe '#name' do
    subject(:name) { event.name }
    it { is_expected.to be :trace_completed }
  end
end
