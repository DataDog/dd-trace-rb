require 'spec_helper'

require 'ddtrace'

RSpec.describe Datadog::Tracer do
  let(:writer) { FauxWriter.new }
  let(:tracer_options) { {} }

  subject(:tracer) { described_class.new(writer: writer, **tracer_options) }

  after { tracer.shutdown! }

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
      end
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

          it do
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
        it 'only the top most span has a runtime ID tag' do
          tracer.trace(name) do |parent_span|
            expect(parent_span.get_tag(Datadog::Ext::Runtime::TAG_ID)).to eq(Datadog::Core::Environment::Identity.id)

            tracer.trace(name) do |child_span|
              expect(child_span.get_tag(Datadog::Ext::Runtime::TAG_ID)).to be nil
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

      context 'when the block raises an error' do
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
    end

    context 'without a block' do
      subject(:trace) { tracer.trace(name, options) }

      context 'with child_of: option' do
        let!(:root_span) { tracer.start_span 'root' }
        let(:options) { { child_of: root_span } }

        it 'creates span with root span parent' do
          tracer.trace 'another' do |_another_span|
            expect(trace.parent).to eq root_span
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

    # Ensure we have a clean OnlyOnce before and after each test
    # so we can properly test the behavior here, and we don't pollute other tests
    before { described_class::SET_SERVICE_INFO_DEPRECATION_WARN_ONLY_ONCE.send(:reset_ran_once_state_for_tests) }

    after { described_class::SET_SERVICE_INFO_DEPRECATION_WARN_ONLY_ONCE.send(:reset_ran_once_state_for_tests) }

    before do
      # Call multiple times to assert we only log once
      allow(Datadog.logger).to receive(:warn).and_call_original

      tracer.set_service_info('service-A', 'app-A', 'app_type-A')
      tracer.set_service_info('service-B', 'app-B', 'app_type-B')
      tracer.set_service_info('service-C', 'app-C', 'app_type-C')
      tracer.set_service_info('service-D', 'app-D', 'app_type-D')
    end

    it 'generates a single deprecation warning' do
      expect(Datadog.logger).to have_received(:warn).once
      expect(log_buffer).to contain_line_with('Usage of set_service_info has been deprecated')
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
end

RSpec.describe Datadog::Tracer::TraceCompleted do
  subject(:event) { described_class.new }

  describe '#name' do
    subject(:name) { event.name }
    it { is_expected.to be :trace_completed }
  end
end
