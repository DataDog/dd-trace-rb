# typed: ignore
require 'spec_helper'
require 'ddtrace/span_operation'

RSpec.describe Datadog::SpanOperation do
  subject(:span_op) { described_class.new(name, options) }
  let(:name) { 'my.operation' }
  let(:options) { {} }

  shared_examples 'a root span operation' do
    it do
      is_expected.to have_attributes(
        parent_id: 0,
        parent: nil,
      )

      # Because we maintain parallel "parent" state between
      # Span and Span Operation, ensure this matches.
      expect(span_op.span).to be_root_span
    end

    it 'has default tags' do
      expect(span_op.get_tag(Datadog::Ext::Runtime::TAG_PID)).to eq(Process.pid)
      expect(span_op.get_tag(Datadog::Ext::Runtime::TAG_ID)).to eq(Datadog::Core::Environment::Identity.id)
    end
  end

  shared_examples 'a child span operation' do
    it 'associates to the parent' do
      expect(span_op).to have_attributes(
        parent: parent,
        parent_id: parent.span_id,
        trace_id: parent.trace_id
      )

      # Because we maintain parallel "parent" state between
      # Span and Span Operation, ensure this matches.
      expect(span_op.span.parent_id).to be(parent.span.span_id)
    end
  end

  shared_context 'parent span operation' do
    let(:parent) { described_class.new('parent', service: parent_service) }
    let(:parent_service) { instance_double(String) }
  end

  shared_context 'callbacks' do
    # rubocop:disable RSpec/VerifiedDoubles
    let(:callback_spy) { spy('callback spy') }
    # rubocop:enable RSpec/VerifiedDoubles

    before do
      # after_finish
      allow(callback_spy).to receive(:after_finish)
      span_op.events.after_finish.subscribe(:test) do |op|
        callback_spy.after_finish(op)
      end

      # before_start
      allow(callback_spy).to receive(:before_start)
      span_op.events.before_start.subscribe(:test) do |op|
        callback_spy.before_start(op)
      end

      # on_error
      allow(callback_spy).to receive(:on_error)
      span_op.events.on_error.subscribe(:test) do |op, e|
        callback_spy.on_error(op, e)
      end
    end
  end

  describe 'forwarded methods' do
    [
      :allocations,
      :clear_metric,
      :clear_tag,
      :duration,
      :duration=,
      :end_time,
      :end_time=,
      :get_metric,
      :get_tag,
      :name,
      :name=,
      :parent_id,
      :parent_id=,
      :pretty_print,
      :resource,
      :resource=,
      :sampled,
      :sampled=,
      :service,
      :service=,
      :set_error,
      :set_metric,
      :set_tag,
      :set_tags,
      :span_id,
      :span_id=,
      :span_type,
      :span_type=,
      :start_time,
      :start_time=,
      :started?,
      :status,
      :status=,
      :stop,
      :stopped?,
      :to_hash,
      :to_json,
      :to_msgpack,
      :to_s,
      :trace_id,
      :trace_id=
    ].each do |forwarded_method|
      # rubocop:disable RSpec/VerifiedDoubles
      context "##{forwarded_method}" do
        let!(:args) { Array.new(arg_count < 0 ? 0 : arg_count) { double('arg') } }
        let!(:arg_count) { span_op.span.method(forwarded_method).arity }

        it 'forwards to the Span' do
          expect(span_op.span).to receive(forwarded_method).with(any_args)
          span_op.send(forwarded_method, *args)
        end
      end
      # rubocop:enable RSpec/VerifiedDoubles
    end
  end

  describe '::new' do
    context 'given only a name' do
      it do
        is_expected.to have_attributes(
          context: nil,
          end_time: nil,
          events: kind_of(described_class::Events),
          finished?: false,
          name: name,
          resource: name,
          sampled: true,
          service: nil,
          span_id: kind_of(Integer),
          span_type: nil,
          span: kind_of(Datadog::Span),
          start_time: nil,
          started?: false,
          stopped?: false,
          trace_id: kind_of(Integer),
        )
      end

      it_behaves_like 'a root span operation'
    end

    context 'given an option' do
      describe ':child_of' do
        let(:options) { { child_of: child_of } }

        context 'that is nil' do
          let(:child_of) { nil }
          it_behaves_like 'a root span operation'
        end

        context 'that is a SpanOperation' do
          include_context 'parent span operation'
          let(:child_of) { parent }

          context 'and no :service is given' do
            it_behaves_like 'a child span operation'

            it 'uses the parent span service' do
              is_expected.to have_attributes(
                service: parent.service
              )
            end
          end

          context 'and :service is given' do
            let(:options) { { child_of: parent, service: service } }
            let(:service) { instance_double(String) }

            it_behaves_like 'a child span operation'

            it 'uses the parent span service' do
              is_expected.to have_attributes(
                service: service
              )
            end
          end
        end
      end

      describe ':context' do
        let(:options) { { context: context } }

        context 'that is nil' do
          let(:context) { nil }

          it_behaves_like 'a root span operation'
        end

        context 'that is a Context' do
          let(:context) { instance_double(Datadog::Context) }

          it_behaves_like 'a root span operation'

          # It should not modify the context:
          # The tracer should be responsible for context management.
          # This association exists only for backwards compatibility.
          it 'associates with the Context' do
            is_expected.to have_attributes(context: context)
          end
        end
      end

      describe ':events' do
        let(:options) { { events: events } }

        context 'that is nil' do
          let(:events) { nil }
          it { is_expected.to have_attributes(events: kind_of(described_class::Events)) }
        end

        context "that is a #{described_class}::Events" do
          let(:events) { instance_double(described_class::Events) }
          it { is_expected.to have_attributes(events: events) }
        end
      end

      describe ':parent_id' do
        let(:options) { { parent_id: parent_id } }

        context 'that is nil' do
          let(:parent_id) { nil }
          it { is_expected.to have_attributes(parent_id: 0) }

          context 'and :child_of is defined' do
            include_context 'parent span operation'
            let(:options) { { child_of: parent, parent_id: parent_id } }

            it_behaves_like 'a child span operation'
          end
        end

        context 'that is an Integer' do
          let(:parent_id) { instance_double(Integer) }
          it { is_expected.to have_attributes(parent_id: parent_id) }

          context 'and :child_of is defined' do
            include_context 'parent span operation'
            let(:options) { { child_of: parent, parent_id: parent_id } }

            # :child_of will override :parent_id, if both are provided.
            it { is_expected.to have_attributes(parent_id: parent.span_id) }
          end
        end
      end

      describe ':resource' do
        let(:options) { { resource: resource } }

        context 'that is nil' do
          let(:resource) { nil }
          # Allow resource to be explicitly set to nil
          it { is_expected.to have_attributes(resource: nil) }
        end

        context 'that is a String' do
          let(:resource) { instance_double(String) }
          it { is_expected.to have_attributes(resource: resource) }
        end
      end

      describe ':service' do
        let(:options) { { service: service } }
        let(:service) { instance_double(String) }

        context 'that is nil' do
          let(:service) { nil }
          it { is_expected.to have_attributes(service: nil) }

          context 'but :child_of is defined' do
            include_context 'parent span operation'
            let(:options) { { child_of: parent, service: service } }

            it_behaves_like 'a child span operation'
            it { is_expected.to have_attributes(service: parent_service) }
          end
        end

        context 'that is a String' do
          let(:service) { instance_double(String) }
          it { is_expected.to have_attributes(service: service) }

          context 'and :child_of is defined' do
            include_context 'parent span operation'
            let(:options) { { child_of: parent, service: service } }

            it_behaves_like 'a child span operation'
            it { is_expected.to have_attributes(service: service) }
          end
        end
      end

      describe ':span_type' do
        let(:options) { { span_type: span_type } }
        let(:span_type) { instance_double(String) }

        context 'that is nil' do
          let(:span_type) { nil }
          it { is_expected.to have_attributes(span_type: nil) }
        end

        context 'that is a String' do
          let(:span_type) { instance_double(String) }
          it { is_expected.to have_attributes(span_type: span_type) }
        end
      end

      describe ':tags' do
        let(:options) { { tags: tags } }

        context 'that is nil' do
          let(:tags) { nil }

          context 'and :child_of is not given' do
            it_behaves_like 'a root span operation'
          end

          context 'and :child_of is given' do
            include_context 'parent span operation'
            let(:options) { { child_of: parent, tags: tags } }

            it_behaves_like 'a child span operation'
          end
        end

        context 'that is a Hash' do
          let(:tags) { { 'custom_tag' => 'custom_value' } }

          context 'and :child_of is not given' do
            it_behaves_like 'a root span operation'
            it { expect(span_op.get_tag('custom_tag')).to eq(tags['custom_tag']) }

            context 'but :tags contains tags that conflict with defaults' do
              let(:tags) do
                {
                  Datadog::Ext::Runtime::TAG_PID => -123,
                  Datadog::Ext::Runtime::TAG_ID => 'custom-id'
                }
              end

              it 'does not override runtime tags' do
                expect(span_op.get_tag(Datadog::Ext::Runtime::TAG_PID)).to eq(Process.pid)
                expect(span_op.get_tag(Datadog::Ext::Runtime::TAG_ID)).to eq(Datadog::Core::Environment::Identity.id)
              end
            end
          end

          context 'and :child_of is given' do
            include_context 'parent span operation'
            let(:options) { { child_of: parent, tags: tags } }

            it_behaves_like 'a child span operation'
            it { expect(span_op.get_tag('custom_tag')).to eq(tags['custom_tag']) }
          end
        end
      end

      describe ':trace_id' do
        let(:options) { { trace_id: trace_id } }

        context 'that is nil' do
          let(:trace_id) { nil }
          it { is_expected.to have_attributes(trace_id: kind_of(Integer)) }
        end

        context 'that is an Integer' do
          let(:trace_id) { Datadog::Utils.next_id }
          it { is_expected.to have_attributes(trace_id: trace_id) }
        end
      end
    end
  end

  describe '#measure' do
    subject(:measure) { span_op.measure(&block) }

    let(:block) do
      allow(block_spy).to receive(:measure).and_return(return_value)
      proc { |op| block_spy.measure(op) }
    end

    let(:return_value) { SecureRandom.uuid }
    # rubocop:disable RSpec/VerifiedDoubles
    let(:block_spy) { spy('block') }
    # rubocop:enable RSpec/VerifiedDoubles

    shared_context 'a StandardError' do
      let(:error) { error_class.new }

      let(:error_class) do
        stub_const('TestError', Class.new(StandardError))
      end
    end

    shared_context 'an Exception' do
      let(:error) { error_class.new }

      let(:error_class) do
        # rubocop:disable Lint/InheritException
        stub_const('TestException', Class.new(Exception))
        # rubocop:enable Lint/InheritException
      end
    end

    context 'when the span has not yet started' do
      it do
        expect { |b| span_op.measure(&b) }
          .to yield_with_args(span_op)
      end

      it 'measures the operation' do
        is_expected.to be return_value
        expect(span_op.started?).to be true
        expect(span_op.finished?).to be true
        expect(span_op.start_time).to_not be nil
        expect(span_op.end_time).to_not be nil
        expect(span_op.status).to eq(0)
      end

      context 'and callbacks have been configured' do
        include_context 'callbacks'

        before { measure }

        it do
          expect(callback_spy).to have_received(:before_start).with(span_op)
          expect(callback_spy).to have_received(:after_finish).with(span_op)
          expect(callback_spy).to_not have_received(:on_error)
        end
      end
    end

    context 'when not given a block' do
      subject(:measure) { span_op.measure }
      it { expect { measure }.to raise_error(ArgumentError) }
    end

    context 'when the operation has already been measured' do
      before { span_op.measure(&block) }
      it { expect { measure }.to raise_error(Datadog::SpanOperation::AlreadyStartedError) }
    end

    context 'when the operation has already been started' do
      before { span_op.start }
      it { expect { measure }.to raise_error(Datadog::SpanOperation::AlreadyStartedError) }
    end

    context 'when the operation has already been finished' do
      before { span_op.finish }
      it { expect { measure }.to raise_error(Datadog::SpanOperation::AlreadyStartedError) }
    end

    context 'when the operation raises a StandardError while starting' do
      include_context 'a StandardError'

      before do
        allow(span_op).to receive(:start).and_raise(error)
        expect(Datadog.logger).to receive(:debug).with(/Failed to start span/)
      end

      it do
        is_expected.to be return_value

        # This scenario is unlikely, but if it occurs
        # expect it to be finished. The timing will be inaccurate,
        # but we need to guarantee the finish event is called.
        expect(span_op.started?).to be true
        expect(span_op.finished?).to be true
        expect(span_op.start_time).to_not be nil
        expect(span_op.end_time).to_not be nil

        # Technically not an error status, because the operation didn't
        # cause the error, the tracing did. This doesn't count.
        expect(span_op.status).to eq(0)
      end

      context 'and callbacks have been configured' do
        include_context 'callbacks'

        before { measure }

        it do
          expect(callback_spy).to_not have_received(:before_start)
          expect(callback_spy).to have_received(:after_finish).with(span_op)
          expect(callback_spy).to_not have_received(:on_error)
        end
      end
    end

    context 'when the operation raises an Exception while starting' do
      include_context 'an Exception'

      before do
        allow(span_op).to receive(:start).and_raise(error)

        # This won't catch exceptions and log them
        expect(Datadog.logger).to_not receive(:debug).with(/Failed to start span/)
      end

      it do
        expect { measure }.to raise_error(error)

        # This scenario is unlikely, but if it occurs
        # expect it to be finished. The timing will be inaccurate,
        # but we need to guarantee the finish event is called.
        expect(span_op.started?).to be true
        expect(span_op.finished?).to be true
        expect(span_op.start_time).to_not be nil
        expect(span_op.end_time).to_not be nil

        # Although this is technically during tracing, not operation,
        # an exception is probably aborting the program. It's fine if
        # this is marked as an error.
        expect(span_op.status).to eq(1)
      end

      context 'and callbacks have been configured' do
        include_context 'callbacks'

        before { expect { measure }.to raise_error(error) }

        it do
          expect(callback_spy).to_not have_received(:before_start)
          expect(callback_spy).to have_received(:after_finish).with(span_op)
          expect(callback_spy).to have_received(:on_error).with(span_op, error)
        end
      end
    end

    context 'when a StandardError is raised during the operation' do
      include_context 'a StandardError'

      let(:block) { proc { raise error } }

      it do
        expect { measure }.to raise_error(error)

        expect(span_op.started?).to be true
        expect(span_op.finished?).to be true
        expect(span_op.start_time).to_not be nil
        expect(span_op.end_time).to_not be nil

        # Technically not an error status, because the operation didn't
        # cause the error, the tracing did. This doesn't count.
        expect(span_op.status).to eq(1)
      end

      context 'and callbacks have been configured' do
        include_context 'callbacks'

        before { expect { measure }.to raise_error(error) }

        it do
          expect(callback_spy).to have_received(:before_start).with(span_op)
          expect(callback_spy).to have_received(:after_finish).with(span_op)
          expect(callback_spy).to have_received(:on_error).with(span_op, error)
        end
      end
    end

    context 'when an Exception is raised during the operation' do
      include_context 'an Exception'

      let(:block) { proc { raise error } }

      it do
        expect { measure }.to raise_error(error)

        expect(span_op.started?).to be true
        expect(span_op.finished?).to be true
        expect(span_op.start_time).to_not be nil
        expect(span_op.end_time).to_not be nil

        # Technically not an error status, because the operation didn't
        # cause the error, the tracing did. This doesn't count.
        expect(span_op.status).to eq(1)
      end

      context 'and callbacks have been configured' do
        include_context 'callbacks'

        before { expect { measure }.to raise_error(error) }

        it do
          expect(callback_spy).to have_received(:before_start).with(span_op)
          expect(callback_spy).to have_received(:after_finish).with(span_op)
          expect(callback_spy).to have_received(:on_error).with(span_op, error)
        end
      end
    end
  end

  describe '#start' do
    shared_examples 'started span' do
      let(:start_time) { kind_of(Time) }

      it { expect { start }.to change { span_op.start_time }.from(nil).to(start_time) }
      # Because span is still running, duration is unavailable.
      it { expect { start }.to_not(change { span_op.duration }) }

      context 'then #stop' do
        before { start }
        it { expect { span_op.stop }.to change { span_op.duration }.from(nil).to(kind_of(Float)) }
      end

      context 'and callbacks have been configured' do
        include_context 'callbacks'
        before { start }
        it { expect(callback_spy).to have_received(:before_start).with(span_op) }
      end
    end

    context 'given nothing' do
      subject(:start) { span_op.start }
      it_behaves_like 'started span'
    end

    context 'given nil' do
      subject(:start) { span_op.start(nil) }
      it_behaves_like 'started span'
    end

    context 'given a Time' do
      subject(:start) { span_op.start(start_time) }

      it_behaves_like 'started span' do
        let(:start_time) { Datadog::Utils::Time.now.utc }
      end
    end

    context 'when already started' do
      subject(:start) { span_op.start }

      let!(:original_start_time) do
        span_op.start
        span_op.start_time
      end

      it 'does not overwrite the previous start time' do
        expect(original_start_time).to_not be nil
        expect { start }.to_not change { span_op.start_time }.from(original_start_time)
      end
    end

    context 'when already stopped' do
      subject(:start) { span_op.start }

      let!(:original_start_time) do
        span_op.start
        span_op.stop
        span_op.start_time
      end

      it 'does not overwrite the previous start time' do
        expect(original_start_time).to_not be nil
        expect { start }.to_not change { span_op.start_time }.from(original_start_time)
      end
    end
  end

  describe '#finish' do
    shared_examples 'finished span' do
      let(:end_time) { kind_of(Time) }

      it { expect { finish }.to change { span_op.end_time }.from(nil).to(end_time) }
      it { expect { finish }.to change { span_op.duration }.from(nil).to(kind_of(Float)) }

      context 'and callbacks have been configured' do
        include_context 'callbacks'
        before { finish }
        it { expect(callback_spy).to have_received(:after_finish).with(span_op) }
      end
    end

    context 'given nothing' do
      subject(:finish) { span_op.finish }
      it_behaves_like 'finished span' do
        before { span_op.start }
      end
    end

    context 'given nil' do
      subject(:finish) { span_op.finish(nil) }
      it_behaves_like 'finished span' do
        before { span_op.start }
      end
    end

    context 'given a Time' do
      subject(:finish) { span_op.finish(end_time) }

      it_behaves_like 'finished span' do
        let(:end_time) { Datadog::Utils::Time.now.utc }
        before { span_op.start }
      end
    end

    context 'when not started' do
      subject(:finish) { span_op.finish }

      it { expect { finish }.to change { span_op.end_time }.from(nil).to(kind_of(Time)) }
      it { expect { finish }.to change { span_op.duration }.from(nil).to(0) }
    end

    context 'when already finished' do
      subject(:finish) { span_op.finish }

      let!(:original_end_time) do
        span_op.start
        span_op.finish
        span_op.end_time
      end

      it 'does not overwrite the previous end time' do
        expect(original_end_time).to_not be nil
        expect { finish }.to_not change { span_op.end_time }.from(original_end_time)
        is_expected.to be(span_op.span)
      end
    end
  end

  describe '#finished?' do
    subject(:finished?) { span_op.finished? }

    context 'when operation hasn\'t been started' do
      it { is_expected.to be false }
    end

    context 'when operation has started but hasn\'t finished' do
      before { span_op.start }
      it { is_expected.to be false }
    end

    context 'when operation is finished' do
      before { span_op.finish }
      it { is_expected.to be true }
    end
  end

  context 'parent=' do
    subject(:set_parent) { span_op.parent = parent }

    context 'to a span' do
      let(:parent) { described_class.new('parent', **parent_span_options) }
      let(:parent_span_options) { {} }

      before do
        parent.sampled = false
        set_parent
      end

      it do
        expect(span_op.parent).to eq(parent)
        expect(span_op.parent_id).to eq(parent.span_id)
        expect(span_op.trace_id).to eq(parent.trace_id)
        expect(span_op.sampled).to eq(false)
      end

      context 'with service' do
        let(:parent_span_options) { { service: 'parent' } }

        it 'copies parent service to child' do
          expect(span_op.service).to eq('parent')
        end

        context 'with existing child service' do
          let(:options) { { service: 'child' } }

          it 'does not override child service' do
            expect(span_op.service).to eq('child')
          end
        end
      end
    end

    context 'to nil' do
      let(:parent) { nil }

      it 'removes the parent' do
        set_parent
        expect(span_op.parent).to be_nil
        expect(span_op.parent_id).to be_zero
        expect(span_op.trace_id).to eq(span_op.span_id)
      end
    end
  end
end

RSpec.describe Datadog::SpanOperation::Events do
  subject(:events) { described_class.new }

  describe '::new' do
    it {
      is_expected.to have_attributes(
        after_finish: kind_of(described_class::AfterFinish),
        before_start: kind_of(described_class::BeforeStart),
        on_error: kind_of(described_class::OnError)
      )
    }

    it 'creates a default #on_error event' do
      expect(events.on_error.subscriptions[:default]).to be(described_class::DEFAULT_ON_ERROR)
    end
  end

  describe '#after_finish' do
    subject(:after_finish) { events.after_finish }
    it { is_expected.to be_a_kind_of(Datadog::Event) }
    it { expect(after_finish.name).to be(:after_finish) }
  end

  describe '#before_start' do
    subject(:before_start) { events.before_start }
    it { is_expected.to be_a_kind_of(Datadog::Event) }
    it { expect(before_start.name).to be(:before_start) }
  end

  describe '#on_error' do
    subject(:on_error) { events.on_error }
    it { is_expected.to be_a_kind_of(Datadog::Event) }
    it { expect(on_error.name).to be(:on_error) }
  end
end

RSpec.describe Datadog::SpanOperation::Analytics do
  subject(:test_object) { test_class.new }

  describe '#set_tag' do
    subject(:set_tag) { test_object.set_tag(key, value) }

    before do
      allow(Datadog::Analytics).to receive(:set_sample_rate)
      set_tag
    end

    context 'when #set_tag is defined on the class' do
      let(:test_class) do
        Class.new do
          prepend Datadog::SpanOperation::Analytics

          # Define this method here to prove it doesn't
          # override behavior in Datadog::Analytics::Span.
          def set_tag(key, value)
            [key, value]
          end
        end
      end

      context 'and is given' do
        context 'some kind of tag' do
          let(:key) { 'my.tag' }
          let(:value) { 'my.value' }

          it 'calls the super #set_tag' do
            is_expected.to eq([key, value])
          end
        end

        context 'TAG_ENABLED with' do
          let(:key) { Datadog::Ext::Analytics::TAG_ENABLED }

          context 'true' do
            let(:value) { true }

            it do
              expect(Datadog::Analytics).to have_received(:set_sample_rate)
                .with(test_object, Datadog::Ext::Analytics::DEFAULT_SAMPLE_RATE)
            end
          end

          context 'false' do
            let(:value) { false }

            it do
              expect(Datadog::Analytics).to have_received(:set_sample_rate)
                .with(test_object, 0.0)
            end
          end

          context 'nil' do
            let(:value) { nil }

            it do
              expect(Datadog::Analytics).to have_received(:set_sample_rate)
                .with(test_object, 0.0)
            end
          end
        end

        context 'TAG_SAMPLE_RATE with' do
          let(:key) { Datadog::Ext::Analytics::TAG_SAMPLE_RATE }

          context 'a Float' do
            let(:value) { 0.5 }

            it do
              expect(Datadog::Analytics).to have_received(:set_sample_rate)
                .with(test_object, value)
            end
          end

          context 'a String' do
            let(:value) { '0.5' }

            it do
              expect(Datadog::Analytics).to have_received(:set_sample_rate)
                .with(test_object, value)
            end
          end

          context 'nil' do
            let(:value) { nil }

            it do
              expect(Datadog::Analytics).to have_received(:set_sample_rate)
                .with(test_object, value)
            end
          end
        end
      end
    end
  end
end

RSpec.describe Datadog::SpanOperation::ManualTracing do
  subject(:test_object) { test_class.new }

  describe '#set_tag' do
    subject(:set_tag) { test_object.set_tag(key, value) }

    before do
      allow(Datadog::ManualTracing).to receive(:keep)
      allow(Datadog::ManualTracing).to receive(:drop)
      set_tag
    end

    context 'when #set_tag is defined on the class' do
      let(:span) do
        instance_double(Datadog::Span).tap do |span|
          allow(span).to receive(:set_tag)
        end
      end

      let(:test_class) do
        s = span

        klass = Class.new do
          prepend Datadog::SpanOperation::ManualTracing
        end

        klass.tap do
          # Define this method here to prove it doesn't
          # override behavior in Datadog::Analytics::Span.
          klass.send(:define_method, :set_tag) do |key, value|
            s.set_tag(key, value)
          end
        end
      end

      context 'and is given' do
        context 'some kind of tag' do
          let(:key) { 'my.tag' }
          let(:value) { 'my.value' }

          it 'calls the super #set_tag' do
            expect(Datadog::ManualTracing).to_not have_received(:keep)
            expect(Datadog::ManualTracing).to_not have_received(:drop)
            expect(span).to have_received(:set_tag)
              .with(key, value)
          end
        end

        context 'TAG_KEEP with' do
          let(:key) { Datadog::Ext::ManualTracing::TAG_KEEP }

          context 'true' do
            let(:value) { true }

            it do
              expect(Datadog::ManualTracing).to have_received(:keep)
                .with(test_object)
              expect(Datadog::ManualTracing).to_not have_received(:drop)
              expect(span).to_not have_received(:set_tag)
            end
          end

          context 'false' do
            let(:value) { false }

            it do
              expect(Datadog::ManualTracing).to_not have_received(:keep)
              expect(Datadog::ManualTracing).to_not have_received(:drop)
              expect(span).to_not have_received(:set_tag)
            end
          end

          context 'nil' do
            let(:value) { nil }

            it do
              expect(Datadog::ManualTracing).to have_received(:keep)
                .with(test_object)
              expect(Datadog::ManualTracing).to_not have_received(:drop)
              expect(span).to_not have_received(:set_tag)
            end
          end
        end

        context 'TAG_DROP with' do
          let(:key) { Datadog::Ext::ManualTracing::TAG_DROP }

          context 'true' do
            let(:value) { true }

            it do
              expect(Datadog::ManualTracing).to_not have_received(:keep)
              expect(Datadog::ManualTracing).to have_received(:drop)
                .with(test_object)
              expect(span).to_not have_received(:set_tag)
            end
          end

          context 'false' do
            let(:value) { false }

            it do
              expect(Datadog::ManualTracing).to_not have_received(:keep)
              expect(Datadog::ManualTracing).to_not have_received(:drop)
              expect(span).to_not have_received(:set_tag)
            end
          end

          context 'nil' do
            let(:value) { nil }

            it do
              expect(Datadog::ManualTracing).to_not have_received(:keep)
              expect(Datadog::ManualTracing).to have_received(:drop)
                .with(test_object)
              expect(span).to_not have_received(:set_tag)
            end
          end
        end
      end
    end
  end
end
