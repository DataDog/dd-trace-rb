require 'spec_helper'

require 'ddtrace'

RSpec.describe Datadog::Tracer do
  include_context 'completed traces'

  # NOTE: Ignore Rubocop rule; described_class changes to match
  #       describe blocks. Describing subclasses will resolve wrong class.
  # rubocop:disable RSpec/DescribedClass
  subject(:tracer) { Datadog::Tracer.new }
  # rubocop:enable RSpec/DescribedClass

  describe '::new' do
    subject(:tracer) { described_class.new(options) }
    let(:options) { {} }

    context 'given :context_provider' do
      subject(:options) { { context_provider: context_provider } }
      let(:context_provider) { instance_double(Datadog::DefaultContextProvider) }
      it { expect(tracer.provider).to be(context_provider) }
    end
  end

  shared_context 'parent span' do
    let(:trace_id) { SecureRandom.uuid }
    let(:span_id) { SecureRandom.uuid }
    let(:service) { 'test-service' }

    before do
      allow(context).to receive(:add_span)
    end

    let(:parent_span) do
      instance_double(
        Datadog::Span,
        context: context,
        trace_id: trace_id,
        span_id: span_id,
        service: service,
        sampled: true
      )
    end

    let(:context) do
      instance_double(
        Datadog::Context,
        trace_id: trace_id,
        span_id: span_id
      )
    end
  end

  describe '#configure' do
    subject!(:configure) { tracer.configure(options) }

    let(:options) { {} }

    it { expect(tracer.context_flush).to be_a(Datadog::ContextFlush::Finished) }

    context 'with partial flushing' do
      let(:options) { { partial_flush: true } }

      it { expect(tracer.context_flush).to be_a(Datadog::ContextFlush::Partial) }
    end
  end

  describe '#default_service' do
    context 'when none is set' do
      it 'obtains it from the script name' do
        expect(tracer.default_service).to eq('rspec')
      end
    end
  end

  describe '#default_service=' do
    let(:service) { 'my-default-service' }

    it 'changes the default service' do
      expect { tracer.default_service = service }
        .to change { tracer.default_service }
        .from('rspec')
        .to(service)
    end
  end

  describe '#tags' do
    subject(:tags) { tracer.tags }

    context 'by default' do
      it { is_expected.to eq({}) }
    end
  end

  describe '#start_span' do
    subject(:start_span) { tracer.start_span(name, options) }

    let(:span) { start_span }
    let(:name) { 'span.name' }
    let(:options) { {} }

    it { is_expected.to be_a_kind_of(Datadog::Span) }

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

    context 'given arguments' do
      include_context 'completed traces'

      subject(:trace) do
        tracer.start_span(
          'op',
          service: 'special-service',
          resource: 'extra-resource',
          span_type: 'my-type',
          start_time: yesterday,
          tags: { 'tag1' => 'value1', 'tag2' => 'value2' }
        ).finish
      end

      let(:yesterday) { Time.now.utc - 24 * 60 * 60 }

      before { tracer.set_tags('env' => 'test', 'temp' => 'cool') }

      it do
        trace

        expect(spans).to have(1).item
        span = spans[0]
        expect(span.service).to eq('special-service')
        expect(span.resource).to eq('extra-resource')
        expect(span.span_type).to eq('my-type')
        expect(span.start_time).to eq(yesterday)
        expect(span.get_tag('env')).to eq('test')
        expect(span.get_tag('temp')).to eq('cool')
        expect(span.get_tag('tag1')).to eq('value1')
        expect(span.get_tag('tag2')).to eq('value2')
        expect(span.get_metric('system.pid')).to be_a_kind_of(Numeric)
      end
    end

    context 'given :child_of with Datadog::Span' do
      include_context 'completed traces'

      it do
        root = tracer.start_span('a')
        root.finish

        first_trace = traces.spans!
        expect(first_trace).to have(1).item
        a = first_trace[0]

        tracer.trace('b') do
          span = tracer.start_span('c', child_of: root)
          span.finish
        end

        second_trace = traces.spans!
        expect(second_trace).to have(2).items
        b, c = second_trace

        expect(a.trace_id).to_not eq(b.trace_id) # Error: a and b do not belong to the same trace
        expect(b.trace_id).to_not eq(c.trace_id) # Error: b and c do not belong to the same trace
        expect(a.trace_id).to eq(c.trace_id) # Error: a and c belong to the same trace
        expect(a.span_id).to eq(c.parent_id) # Error: a is the parent of c
      end
    end

    context 'given :child_of with Datadog::Context' do
      include_context 'completed traces'

      let(:mutex) { Mutex.new }

      it do
        @thread_span = nil
        @thread_ctx = nil

        mutex.lock
        thread = Thread.new do
          @thread_span = tracer.start_span('a')
          @thread_ctx = @thread_span.context
          mutex.lock
          mutex.unlock
        end

        try_wait_until { @thread_ctx && @thread_span }

        expect(tracer.call_context).to_not be @thread_ctx

        tracer.trace('b') do
          span = tracer.start_span('c', child_of: @thread_ctx)
          span.finish
        end

        @thread_span.finish
        mutex.unlock
        thread.join

        @thread_span = nil
        @thread_ctx = nil

        expect(spans).to have(3).items
        a, b, c = spans
        expect(a.trace_id).to_not eq(b.trace_id) # Error: a and b do not belong to the same trace
        expect(b.trace_id).to_not eq(c.trace_id) # Error: b and c do not belong to the same trace
        expect(a.trace_id).to eq(c.trace_id) # Error: a and c belong to the same trace
        expect(a.span_id).to eq(c.parent_id) # Error: a is the parent of c
      end
    end

    context 'when concurrent with another trace' do
      include_context 'completed traces'

      subject(:trace) do
        main = tracer.trace('main_call')
        detached = tracer.start_span('detached_trace')
        detached.finish
        main.finish
      end

      it do
        trace

        expect(spans).to have(2).items
        d, m = spans

        expect(m.name).to eq('main_call')
        expect(d.name).to eq('detached_trace')
        expect(m.trace_id).to_not eq(d.trace_id) # Error: trace IDs should be different
        expect(m.span_id).to_not eq(d.parent_id) # Error: m should not be the parent of d
        expect(m.parent_id).to eq(0) # Error: m should be a root span
        expect(d.parent_id).to eq(0) # Error: d should be a root span
      end
    end
  end

  describe '#trace' do
    let(:name) { 'span.name' }
    let(:options) { {} }

    context 'given a block' do
      subject(:trace) { tracer.trace(name, options, &block) }

      let(:block) { proc { result } }
      let(:result) { double('result') }

      context 'when starting a span' do
        it do
          expect { |b| tracer.trace(name, &b) }.to yield_with_args(
            a_kind_of(Datadog::Span)
          )
        end

        it { expect(trace).to eq(result) }

        it 'publishes the trace' do
          expect(tracer.trace_completed).to receive(:publish) do |trace|
            # Trace should be an array
            expect(trace).to be_a_kind_of(Array)
            expect(trace).to have(1).item

            # First item should be a span
            span = trace.first
            expect(span).to be_a_kind_of(Datadog::Span)
            expect(span.name).to eq name
            expect(span.to_hash[:duration]).to > 0
          end

          trace
        end

        it 'tracks the number of allocations made in the span' do
          skip 'Test unstable; improve stability before re-enabling.'
          skip 'Not supported for Ruby < 2.0' if Gem::Version.new(RUBY_VERSION) < Gem::Version.new('2.0.0')

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

          it do
            expect(Datadog.logger).to receive(:debug).with(including('Writing 1 span'))
            expect(Datadog.logger).to receive(:debug).with(including('Name: span.name'))

            subject
          end
        end

        it 'adds a runtime ID tag to the span' do
          tracer.trace(name) do |span|
            expect(span.get_tag(Datadog::Ext::Runtime::TAG_ID)).to eq(Datadog::Runtime::Identity.id)
          end
        end
      end

      context 'when nesting spans' do
        it 'only the top most span has a runtime ID tag' do
          tracer.trace(name) do |parent_span|
            expect(parent_span.get_tag(Datadog::Ext::Runtime::TAG_ID)).to eq(Datadog::Runtime::Identity.id)

            tracer.trace(name) do |child_span|
              expect(child_span.get_tag(Datadog::Ext::Runtime::TAG_ID)).to be nil
            end
          end
        end

        context 'with forking' do
          before { skip 'Fork not supported on current platform' unless Process.respond_to?(:fork) }

          it 'only the top most span per process has a runtime ID tag' do
            tracer.trace(name) do |parent_span|
              parent_process_id = Datadog::Runtime::Identity.id
              expect(parent_span.get_tag(Datadog::Ext::Runtime::TAG_ID)).to eq(parent_process_id)

              tracer.trace(name) do |child_span|
                expect(child_span.get_tag(Datadog::Ext::Runtime::TAG_ID)).to be nil

                expect_in_fork do
                  fork_process_id = Datadog::Runtime::Identity.id
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

      context 'when starting a span fails' do
        before do
          allow(tracer).to receive(:start_span).and_raise(error)
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
            allow(tracer).to receive(:start_span).and_raise(fatal_error)
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

      context 'when the block raises a StandardError' do
        let(:block) { proc { raise error } }
        let(:error) { error_class.new }
        let(:error_class) { Class.new(StandardError) }

        context 'and the on_error option' do
          context 'is not provided' do
            it do
              expect_any_instance_of(Datadog::Span).to receive(:set_error)
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
                  a_kind_of(Datadog::Span),
                  error
                )
              end.to raise_error(error)

              expect(spans).to have(1).item
              expect(spans[0]).to_not have_error
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

      context 'when the block raises an Exception' do
        let(:block) { proc { raise error } }
        let(:error) { error_class.new }
        let(:error_class) { Class.new(Exception) }

        context 'and the on_error option' do
          context 'is not provided' do
            it do
              expect_any_instance_of(Datadog::Span).to receive(:set_error)
                .with(error)
              expect { trace }.to raise_error(error)
            end
          end

          context 'is a block' do
            it 'yields to the error block and raises the error' do
              expect_any_instance_of(Datadog::Span).to_not receive(:set_error)
              expect do
                expect do |b|
                  tracer.trace(name, on_error: b.to_proc, &block)
                end.to yield_with_args(
                  a_kind_of(Datadog::Span),
                  error
                )
              end.to raise_error(error)
            end
          end
        end
      end
    end

    context 'given a block with arguments' do
      include_context 'completed traces'

      subject(:trace) do
        tracer.trace(
          'op',
          service: 'special-service',
          resource: 'extra-resource',
          span_type: 'my-type',
          tags: { 'tag1' => 'value1', 'tag2' => 'value2' }
        ) do
        end
      end

      before { tracer.set_tags('env' => 'test', 'temp' => 'cool') }

      it do
        trace

        expect(spans).to have(1).item
        span = spans[0]
        expect(span.service).to eq('special-service')
        expect(span.resource).to eq('extra-resource')
        expect(span.span_type).to eq('my-type')

        expect(span.get_tag('env')).to eq('test')
        expect(span.get_tag('temp')).to eq('cool')
        expect(span.get_tag('tag1')).to eq('value1')
        expect(span.get_tag('tag2')).to eq('value2')
        expect(span.get_metric('system.pid')).to be_a_kind_of(Numeric)
      end
    end

    context 'without a block' do
      subject(:trace) { tracer.trace(name, options) }

      it { is_expected.to be_a_kind_of(Datadog::Span) }
      it { expect(trace.name).to eq(name) }
      it { expect(trace.end_time).to be nil }
    end

    context 'when disabled' do
      include_context 'completed traces'

      before { tracer.enabled = false }

      it 'does not publish traces' do
        tracer.trace('something').finish
        expect(spans).to be_empty
      end
    end

    context 'when resource is nil' do
      include_context 'completed traces'

      subject(:trace) do
        tracer.trace('resource_set_to_nil', resource: nil) do |s|
          # Testing passing of nil resource, some parts of the code
          # rely on explicitly saying resource should be nil (pitfall: refactor
          # and merge hash, then forget to pass resource: nil, this has side
          # effects on Rack, while a rack unit test should trap this, it's unclear
          # then, so this test is here to catch the problem early on).
          expect(s.resource).to be nil
        end

        tracer.trace('resource_set_to_default') do |s|
        end
      end

      it do
        trace

        expect(spans).to have(2).items
        resource_set_to_default, resource_set_to_nil = spans

        expect(resource_set_to_nil.resource).to be nil
        expect(resource_set_to_nil.name).to eq('resource_set_to_nil')

        expect(resource_set_to_default.resource).to eq('resource_set_to_default')
        expect(resource_set_to_default.name).to eq('resource_set_to_default')
      end
    end

    context 'when span is a child' do
      subject(:trace) do
        tracer.trace('something')
        tracer.trace('something_else')
      end

      it { expect(trace.get_tag('system.pid')).to be nil }
    end

    context 'that has children' do
      include_context 'completed traces'

      subject(:trace) do
        tracer.trace('a', service: 'parent') do
          tracer.trace('b') { |s| s.set_tag('a', 'a') }
          tracer.trace('c', service: 'other') { |s| s.set_tag('b', 'b') }
        end
      end

      it 'has the correct relationships' do
        trace
        expect(spans).to have(3).items

        a, b, c = spans

        expect(a.name).to eq('a')
        expect(b.name).to eq('b')
        expect(c.name).to eq('c')
        expect(a.trace_id).to eq(b.trace_id)
        expect(a.trace_id).to eq(c.trace_id)
        expect(a.span_id).to eq(b.parent_id)
        expect(a.span_id).to eq(c.parent_id)

        expect(a.service).to eq('parent')
        expect(b.service).to eq('parent')
        expect(c.service).to eq('other')
      end
    end

    context 'that has a child that finishes after the parent' do
      it 'doesn\'t associate a 2nd trace with the previous child span' do
        t1 = tracer.trace('t1')
        t1_child = tracer.trace('t1_child')
        expect(t1_child.parent).to eq(t1)

        t1.finish
        t1_child.finish

        t2 = tracer.trace('t2')
        expect(t2.parent).to be nil
      end
    end
  end

  describe '#call_context' do
    subject(:call_context) { tracer.call_context }

    let(:context) { instance_double(Datadog::Context) }

    context 'given no arguments' do
      it do
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

      it do
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

      it do
        expect(tracer.call_context).to receive(:current_span).and_return(span)
        is_expected.to be(span)
      end
    end

    context 'given a key' do
      subject(:active_span) { tracer.active_span(key) }

      let(:key) { double('key') }

      it do
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

      it do
        expect(tracer.call_context).to receive(:current_root_span).and_return(span)
        is_expected.to be(span)
      end
    end

    context 'given a key' do
      subject(:active_root_span) { tracer.active_root_span(key) }

      let(:key) { double('key') }

      it do
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

  describe '#set_service_info' do
    include_context 'tracer logging'

    # Ensure we have a clean `@done_once` before and after each test
    # so we can properly test the behavior here, and we don't pollute other tests
    before { Datadog::Patcher.instance_variable_set(:@done_once, nil) }

    after { Datadog::Patcher.instance_variable_set(:@done_once, nil) }

    before do
      # Call multiple times to assert we only log once
      tracer.set_service_info('service-A', 'app-A', 'app_type-A')
      tracer.set_service_info('service-B', 'app-B', 'app_type-B')
      tracer.set_service_info('service-C', 'app-C', 'app_type-C')
      tracer.set_service_info('service-D', 'app-D', 'app_type-D')
    end

    it 'generates a single deprecation warnings' do
      expect(log_buffer.length).to be > 1
      expect(log_buffer).to contain_line_with('Usage of set_service_info has been deprecated')
    end
  end

  describe '#set_tags' do
    subject(:set_tags) { tracer.set_tags(tags) }

    context 'set before a trace' do
      before { tracer.set_tags('env' => 'test', 'component' => 'core') }

      it 'sets the tags on the trace' do
        span = tracer.trace('something')
        expect(span.get_tag('env')).to eq('test')
        expect(span.get_tag('component')).to eq('core')
      end
    end

    context 'when equivalent String and Symbols are added' do
      shared_examples 'equivalent tags' do
        subject(:tags) { tracer.tags }

        it 'retains the tag only as a String' do
          is_expected.to include('host')
          is_expected.to_not include(:host)
        end

        it 'retains only the last value' do
          is_expected.to include('host' => 'b')
        end
      end

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
    end
  end

  describe '#record' do
    subject(:record) { tracer.record(context) }
    let(:context) { instance_double(Datadog::Context) }

    before do
      allow(tracer.trace_completed).to receive(:publish)
    end

    context 'with trace' do
      let(:trace) { [Datadog::Span.new(tracer, 'dummy')] }

      before do
        expect_any_instance_of(Datadog::ContextFlush::Finished)
          .to receive(:consume!).with(context).and_return(trace)

        subject
      end

      it do
        expect(tracer.trace_completed)
          .to have_received(:publish)
          .with(trace)
      end
    end

    context 'with empty trace' do
      let(:trace) { [] }

      it do
        expect(tracer.trace_completed)
          .to_not have_received(:publish)
      end
    end

    context 'with nil trace' do
      let(:trace) { nil }

      it do
        expect(tracer.trace_completed)
          .to_not have_received(:publish)
      end
    end
  end

  describe '#trace_completed' do
    subject(:trace_completed) { tracer.trace_completed }
    it { is_expected.to be_a_kind_of(described_class::TraceCompleted) }
  end

  # TODO: Re-enable. Shared context "completed traces" didn't like this.
  describe described_class::TraceCompleted do
    let(:event) { described_class.new }

    describe '#name' do
      subject(:name) { event.name }
      it { is_expected.to be :trace_completed }
    end
  end
end
