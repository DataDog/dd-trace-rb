# typed: false
require 'spec_helper'

require 'ddtrace'

RSpec.describe Datadog::Tracer do
  let(:writer) { FauxWriter.new }
  let(:tracer_options) { {} }

  subject(:tracer) { described_class.new(writer: writer, **tracer_options) }

  after { tracer.shutdown! }

  shared_context 'parent span' do
    let(:parent_span) { tracer.start_span('parent', service: service) }
    let(:service) { 'test-service' }
    let(:trace_id) { parent_span.trace_id }
    let(:span_id) { parent_span.span_id }
  end

  describe '::new' do
    context 'given :context_flush' do
      let(:tracer_options) { super().merge(context_flush: context_flush) }
      let(:context_flush) { instance_double(Datadog::ContextFlush::Finished) }
      it { is_expected.to have_attributes(context_flush: context_flush) }
    end
  end

  describe '#configure' do
    context 'by default' do
      subject!(:configure) { tracer.configure(options) }

      let(:options) { {} }

      it { expect(tracer.context_flush).to be_a(Datadog::ContextFlush::Finished) }
    end

    context 'with context flush' do
      subject!(:configure) { tracer.configure(options) }

      let(:options) { { context_flush: context_flush } }
      let(:context_flush) { instance_double(Datadog::ContextFlush::Finished) }

      it { expect(tracer.context_flush).to be(context_flush) }
    end

    context 'with partial flushing' do
      subject!(:configure) { tracer.configure(options) }

      let(:options) { { partial_flush: true } }

      it { expect(tracer.context_flush).to be_a(Datadog::ContextFlush::Partial) }
    end

    context 'with agent_settings' do
      subject(:configure) { tracer.configure(options) }

      let(:agent_settings) { double('agent_settings') }
      let(:options) { { agent_settings: agent_settings } }

      it 'creates a new writer using the given agent_settings' do
        # create writer first, to avoid colliding with the below expectation
        writer

        expect(Datadog::Writer).to receive(:new).with(hash_including(agent_settings: agent_settings))

        configure
      end
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

  describe '#start_span' do
    subject(:start_span) { tracer.start_span(name, options) }

    let(:span) { start_span }
    let(:name) { 'span.name' }
    let(:options) { {} }

    it { is_expected.to be_a_kind_of(Datadog::SpanOperation) }

    it 'belongs to current the context by default' do
      tracer.trace('parent') do |active_span|
        expect(start_span.parent).to eq(active_span)
        expect(start_span.context).to eq(active_span.context)
      end
    end

    context 'when :tags are given' do
      let(:options) { super().merge(tags: tags) }
      let(:tags) { { tag_name => tag_value } }
      let(:tag_name) { 'my-tag' }
      let(:tag_value) { 'my-value' }

      it { expect(span.get_tag(tag_name)).to eq(tag_value) }

      context 'and default tags are set on the tracer' do
        let(:default_tags) { { default_tag_name => default_tag_value } }
        let(:default_tag_name) { 'default_tag' }
        let(:default_tag_value) { 'default_value' }

        before { tracer.set_tags(default_tags) }

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

    context 'when :child_of' do
      context 'is not given' do
        it 'applies a runtime ID tag' do
          expect(start_span.get_tag(Datadog::Ext::Runtime::TAG_ID)).to eq(Datadog::Core::Environment::Identity.id)
        end
      end

      context 'is given' do
        include_context 'parent span'

        let(:options) { super().merge(child_of: parent_span) }

        it 'does not apply a runtime ID tag' do
          expect(start_span.get_tag(Datadog::Ext::Runtime::TAG_ID)).to be nil
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
          let(:tags) { { 'my' => 'tag' } }

          it 'sets the span tags' do
            expect(span.get_tag('my')).to eq('tag')
          end
        end
      end
    end

    context 'given a block' do
      subject(:trace) { tracer.trace(name, options, &block) }

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
            a_kind_of(Datadog::SpanOperation)
          )
        end

        it 'returns block result' do
          expect(trace).to eq(result)
        end

        it 'sets the span name from the name argument' do
          trace
          expect(span.name).to eq(name)
        end

        it 'tracks the number of allocations made in the span' do
          skip 'Test unstable; improve stability before re-enabling.'

          # Create and discard first trace.
          # When warming up, it might have more allocations than subsequent traces.
          tracer.trace(name) {}
          writer.spans

          # Then create traces to compare
          tracer.trace(name) {}
          tracer.trace(name) { Object.new }

          first, second = writer.spans

          # Different versions of Ruby will allocate a different number of
          # objects, so this is what works across the board.
          expect(second.allocations).to eq(first.allocations + 1)
        end

        context 'with diagnostics debug enabled' do
          before do
            Datadog.configure do |c|
              c.diagnostics.debug = true
            end

            allow(writer).to receive(:write)
          end

          it 'records span flushing to logger' do
            expect(Datadog.logger).to receive(:debug).with(including('Writing 1 span'))
            expect(Datadog.logger).to receive(:debug).with(including('Name: span.name'))

            subject
          end
        end

        it 'adds a runtime ID tag to the span' do
          tracer.trace(name) do |span|
            expect(span.get_tag(Datadog::Ext::Runtime::TAG_ID)).to eq(Datadog::Core::Environment::Identity.id)
          end
        end
      end

      context 'when nesting spans' do
        it 'propagates parent span and service name to children' do
          tracer.trace('parent', service: 'service-parent') do
            tracer.trace('child1') { |s| s.set_tag('tag', 'tag_1') }
            tracer.trace('child2', service: 'service-child2') { |s| s.set_tag('tag', 'tag_2') }
          end

          expect(spans).to have(3).items

          child1, child2, parent = spans # Spans are sorted alphabetically by operation name

          expect(parent.parent).to be_nil
          expect(parent.name).to eq('parent')
          expect(parent.service).to eq('service-parent')

          expect(child1.parent).to be(parent)
          expect(child1.name).to eq('child1')
          expect(child1.service).to eq('service-parent')
          expect(child1.get_tag('tag')).to eq('tag_1')

          expect(child2.parent).to be(parent)
          expect(child2.name).to eq('child2')
          expect(child2.service).to eq('service-child2')
          expect(child2.get_tag('tag')).to eq('tag_2')
        end

        it 'only the top most span has a runtime ID and PID tags' do
          tracer.trace(name) do |parent_span|
            expect(parent_span.get_tag('runtime-id')).to eq(Datadog::Core::Environment::Identity.id)
            expect(parent_span.get_tag('system.pid')).to eq(Process.pid)

            tracer.trace(name) do |child_span|
              expect(child_span.get_tag('runtime-id')).to be_nil
              expect(child_span.get_tag('system.pid')).to be_nil
            end
          end
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

              expect(grandparent.parent).to be nil
              expect(parent.parent).to be grandparent
              expect(child.parent).to be parent
              expect(grandchild.parent).to be child
              expect(uncle.parent).to be grandparent
              expect(nephew.parent).to be uncle
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

            # TODO: Skip for now, but keep this test because it demonstrates something we should fix.
            before { skip('There is no fix currently available for this failure.') }

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
              expect(grandparent.parent).to be nil
              expect(parent.parent).to be grandparent
              expect(child.parent).to be parent
              expect(grandchild.parent).to be child

              expect(
                [
                  great_uncle,
                  second_cousin
                ].all? { |s| s.trace_id == great_uncle.trace_id }
              ).to be true
              expect(great_uncle.parent).to be nil
              expect(second_cousin.parent).to be great_uncle

              # Should be separate traces (can't have two root spans for a trace)
              # TODO: This fails because when "grandparent" completes, it has unfinished
              #       spans still present in the context. This prevents the context from resetting.
              #       Thus when "great uncle" starts, it still shares the same trace ID as "grandparent"
              #
              #       When unfinished spans are present at trace complete, we need to decide what to do.
              #       We could detach the context from the thread, and give the thread a new context.
              #       This way unfinished spans could complete later, without holding the current context hostage.
              #       However, this has a risk of causing Context objects to leak, if each unfinished span is
              #       somehow held onto by instrumentation.
              expect(grandparent.trace_id).to_not eq(great_uncle.trace_id)
            end
          end
        end

        context 'with forking' do
          before { skip 'Fork not supported on current platform' unless Process.respond_to?(:fork) }

          it 'only the top most span per process has a runtime ID tag' do
            tracer.trace(name) do |parent_span|
              parent_process_id = Datadog::Core::Environment::Identity.id
              expect(parent_span.get_tag(Datadog::Ext::Runtime::TAG_ID)).to eq(parent_process_id)

              tracer.trace(name) do |child_span|
                expect(child_span.get_tag(Datadog::Ext::Runtime::TAG_ID)).to be nil

                expect_in_fork do
                  fork_process_id = Datadog::Core::Environment::Identity.id
                  expect(fork_process_id).to_not eq(parent_process_id)

                  tracer.trace(name) do |fork_parent_span|
                    # Tag should be set on the fork's parent span, but not be the same as the parent process runtime ID
                    expect(fork_parent_span.get_tag(Datadog::Ext::Runtime::TAG_ID)).to eq(fork_process_id)
                    expect(fork_parent_span.get_tag(Datadog::Ext::Runtime::TAG_ID)).to_not eq(parent_process_id)

                    tracer.trace(name) do |fork_child_span|
                      expect(fork_child_span.get_tag(Datadog::Ext::Runtime::TAG_ID)).to be nil
                    end
                  end
                end
              end
            end
          end
        end
      end

      context 'when building a span fails' do
        before do
          allow(tracer).to receive(:build_span).and_raise(error)
        end

        let(:error) { error_class.new }
        let(:error_class) { Class.new(StandardError) }

        it 'still yields to the block and does not raise an error' do
          expect do
            expect do |b|
              tracer.trace(name, &b)
            end.to yield_with_args(nil)
          end.to_not raise_error
        end

        context 'with fatal exception' do
          let(:fatal_error) { stub_const('FatalError', Class.new(Exception)) }

          before do
            # Raise error at first line of begin block
            allow(tracer).to receive(:build_span).and_raise(fatal_error)
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
          let(:error_class) { stub_const('CriticalError', Class.new(Exception)) }

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
              expect_any_instance_of(Datadog::SpanOperation).to receive(:set_error)
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
                  a_kind_of(Datadog::SpanOperation),
                  error
                )
              end.to raise_error(error)

              expect(span).to_not have_error
            end
          end

          context 'is a block that is not a Proc' do
            let(:not_a_proc_block) { 'not a proc' }

            it 'fallbacks to default error handler and log a debug message' do
              expect_any_instance_of(Datadog::Logger).to receive(:debug).at_least(:once)
              expect do
                tracer.trace(name, on_error: not_a_proc_block, &block)
              end.to raise_error(error)
            end
          end
        end
      end
    end

    context 'without a block' do
      subject(:trace) { tracer.trace(name, options) }

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

      context 'with child_of: option' do
        let(:options) { { child_of: child_of_value } }

        context 'as a span' do
          let!(:parent_span) { tracer.trace('parent') }
          let(:child_of_value) { parent_span }

          it 'creates span with specified parent' do
            tracer.trace 'another' do
              expect(trace.parent).to eq parent_span
              expect(trace.context).to eq parent_span.context
            end
          end
        end

        context 'as a context' do
          let(:context) { Datadog::Context.new }
          let(:child_of_value) { context }

          it 'creates span with specified context' do
            tracer.trace 'another' do
              expect(trace.parent).to be_nil
              expect(trace.context).to eq context
            end
          end
        end
      end

      context 'without child_of: option' do
        let(:options) { {} }

        it 'creates span with current context' do
          tracer.trace 'root' do |_root_span|
            tracer.trace 'another' do |another_span|
              expect(trace.parent).to eq another_span
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

          expect(parent.parent).to be_nil
          expect(child.parent).to be(parent)
          expect(child.end_time).to be > parent.end_time
        end
      end
    end
  end

  describe '#call_context' do
    subject(:call_context) { tracer.call_context }

    let(:context) { instance_double(Datadog::Context) }

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
      subject(:call_context) { tracer.call_context(key) }

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

  describe '#active_span' do
    let(:span) { instance_double(Datadog::Span) }
    let(:call_context) { instance_double(Datadog::Context) }

    context 'given no arguments' do
      subject(:active_span) { tracer.active_span }

      it 'returns the currently active, default active span' do
        expect(tracer.call_context).to receive(:current_span).and_return(span)
        is_expected.to be(span)
      end
    end

    context 'given a key' do
      subject(:active_span) { tracer.active_span(key) }

      let(:key) { double('key') }

      it 'returns the active span associated with the key' do
        expect(tracer)
          .to receive(:call_context)
          .with(key)
          .and_return(call_context)

        expect(call_context)
          .to receive(:current_span)
          .and_return(span)

        is_expected.to be(span)
      end
    end
  end

  describe '#active_root_span' do
    let(:span) { instance_double(Datadog::Span) }
    let(:call_context) { instance_double(Datadog::Context) }

    context 'given no arguments' do
      subject(:active_root_span) { tracer.active_root_span }

      it 'returns the currently active, default root span' do
        expect(tracer.call_context).to receive(:current_root_span).and_return(span)
        is_expected.to be(span)
      end
    end

    context 'given a key' do
      subject(:active_root_span) { tracer.active_root_span(key) }

      let(:key) { double('key') }

      it 'returns the root span associated with the key' do
        expect(tracer)
          .to receive(:call_context)
          .with(key)
          .and_return(call_context)

        expect(call_context)
          .to receive(:current_root_span)
          .and_return(span)

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

      it 'produces an Datadog::Correlation::Identifier with data' do
        is_expected.to be_a_kind_of(Datadog::Correlation::Identifier)
        expect(active_correlation.trace_id).to eq(span.trace_id)
        expect(active_correlation.span_id).to eq(span.span_id)
      end
    end

    context 'when no trace is active' do
      it 'produces an empty Datadog::Correlation::Identifier' do
        is_expected.to be_a_kind_of(Datadog::Correlation::Identifier)
        expect(active_correlation.trace_id).to eq 0
        expect(active_correlation.span_id).to eq 0
      end
    end

    context 'given a key' do
      subject(:active_correlation) { tracer.active_correlation(key) }

      let(:key) { Thread.current }
      let(:call_context) { instance_double(Datadog::Context) }

      it 'returns a correlation that matches that context' do
        expect(tracer)
          .to receive(:call_context)
          .with(key)
          .and_call_original

        is_expected.to be_a_kind_of(Datadog::Correlation::Identifier)
      end
    end
  end

  describe '#record' do
    subject(:record) { tracer.record(context) }
    let(:context) { instance_double(Datadog::Context) }

    before do
      allow(tracer.trace_completed).to receive(:publish)
    end

    context 'with trace' do
      let(:trace) { [Datadog::Span.new('dummy')] }

      before do
        expect_any_instance_of(Datadog::ContextFlush::Finished)
          .to receive(:consume!).with(context).and_return(trace)

        subject
      end

      it 'writes the trace' do
        expect(writer.spans).to eq(trace)

        expect(tracer.trace_completed)
          .to have_received(:publish)
          .with(trace)
      end
    end

    context 'with empty trace' do
      let(:trace) { [] }

      it 'does not write a trace' do
        expect(writer.spans).to be_empty

        expect(tracer.trace_completed)
          .to_not have_received(:publish)
      end
    end

    context 'with nil trace' do
      let(:trace) { nil }

      it 'does not write a trace' do
        expect(writer.spans).to be_empty

        expect(tracer.trace_completed)
          .to_not have_received(:publish)
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
end

RSpec.describe Datadog::Tracer::TraceCompleted do
  subject(:event) { described_class.new }

  describe '#name' do
    subject(:name) { event.name }
    it { is_expected.to be :trace_completed }
  end
end
