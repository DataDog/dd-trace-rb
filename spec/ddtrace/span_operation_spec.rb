# typed: ignore
require 'spec_helper'
require 'ddtrace/span_operation'

RSpec.describe Datadog::SpanOperation do
  subject(:span_op) { described_class.new(name, **options) }
  let(:name) { 'my.operation' }
  let(:options) { {} }

  shared_examples 'a root span operation' do
    it do
      is_expected.to have_attributes(
        parent_id: 0,
        parent: nil,
      )
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
      events = span_op.send(:events)

      # after_finish
      allow(callback_spy).to receive(:after_finish)
      events.after_finish.subscribe(:test) do |*args|
        callback_spy.after_finish(*args)
      end

      # after_stop
      allow(callback_spy).to receive(:after_stop)
      events.after_stop.subscribe(:test) do |*args|
        callback_spy.after_stop(*args)
      end

      # before_start
      allow(callback_spy).to receive(:before_start)
      events.before_start.subscribe(:test) do |*args|
        callback_spy.before_start(*args)
      end

      # on_error
      allow(callback_spy).to receive(:on_error)
      events.on_error.subscribe(:test) do |*args|
        callback_spy.on_error(*args)
      end
    end
  end

  describe '::new' do
    context 'given only a name' do
      it 'has default attributes' do
        is_expected.to have_attributes(
          context: nil,
          end_time: nil,
          id: kind_of(Integer),
          name: name,
          parent_id: 0,
          resource: name,
          sampled: true,
          service: nil,
          start_time: nil,
          status: 0,
          trace_id: kind_of(Integer),
          type: nil
        )
      end

      it 'has default behavior' do
        is_expected.to have_attributes(
          allocations: 0,
          duration: nil,
          finished?: false,
          started?: false,
          stopped?: false
        )
      end

      it 'aliases #span_id' do
        expect(span_op.id).to eq(span_op.span_id)
      end

      it 'aliases #span_type' do
        expect(span_op.type).to eq(span_op.span_type)
      end

      it 'aliases #span_type= to #type=' do
        span_type = 'foo'
        span_op.span_type = 'foo'
        expect(span_op.type).to eq(span_type)
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

      describe ':start_time' do
        let(:options) { { start_time: start_time } }
        let(:start_time) { instance_double(Time) }

        context 'that is nil' do
          let(:start_time) { nil }
          it { is_expected.to have_attributes(start_time: nil) }
        end

        context 'that is a Time' do
          let(:start_time) { instance_double(Time) }
          it { is_expected.to have_attributes(start_time: start_time) }
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

      describe ':type' do
        let(:options) { { type: type } }
        let(:type) { instance_double(String) }

        context 'that is nil' do
          let(:type) { nil }
          it { is_expected.to have_attributes(type: nil) }

          context 'but :span_type is given' do
            let(:options) { { type: nil, span_type: type } }
            it { is_expected.to have_attributes(type: type) }
          end
        end

        context 'that is a String' do
          let(:type) { instance_double(String) }
          it { is_expected.to have_attributes(type: type) }
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
          expect(callback_spy).to have_received(:before_start).with(span_op).ordered
          expect(callback_spy).to have_received(:after_stop).with(span_op).ordered
          expect(callback_spy).to have_received(:after_finish).with(kind_of(Datadog::Span), span_op).ordered
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
          expect(callback_spy).to have_received(:before_start).with(span_op).ordered
          expect(callback_spy).to have_received(:after_stop).with(span_op).ordered
          expect(callback_spy).to have_received(:on_error).with(span_op, error).ordered
          expect(callback_spy).to have_received(:after_finish).with(kind_of(Datadog::Span), span_op).ordered
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
          expect(callback_spy).to have_received(:before_start).with(span_op).ordered
          expect(callback_spy).to have_received(:after_stop).with(span_op).ordered
          expect(callback_spy).to have_received(:on_error).with(span_op, error).ordered
          expect(callback_spy).to have_received(:after_finish).with(kind_of(Datadog::Span), span_op).ordered
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
      let(:start_time) { Datadog::Utils::Time.now.utc }

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
        it { expect(callback_spy).to_not have_received(:before_start) }
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

  describe '#stop' do
    subject(:stop) { span_op.stop }

    shared_examples 'stopped span' do
      let(:end_time) { kind_of(Time) }

      context 'which wasn\'t already started' do
        it { expect { stop }.to change { span_op.start_time }.from(nil).to(end_time) }
        it { expect { stop }.to change { span_op.end_time }.from(nil).to(end_time) }
        it { expect { stop }.to change { span_op.duration }.from(nil).to(kind_of(Float)) }

        it { expect { stop }.to change { span_op.started? }.from(false).to(true) }
        it { expect { stop }.to change { span_op.stopped? }.from(false).to(true) }
        it { expect { stop }.to_not change { span_op.finished? }.from(false) }

        context 'and callbacks have been configured' do
          include_context 'callbacks'
          before { stop }
          it do
            expect(callback_spy).to have_received(:after_stop).with(span_op)
            expect(callback_spy).to_not have_received(:before_start)
            expect(callback_spy).to_not have_received(:after_finish)
          end
        end
      end

      context 'when already started' do
        let!(:start_time) { span_op.start_time = Time.now }

        it { expect { stop }.to_not change { span_op.start_time }.from(start_time) }
        it { expect { stop }.to change { span_op.end_time }.from(nil).to(end_time) }
        it { expect { stop }.to change { span_op.duration }.from(nil).to(kind_of(Float)) }

        it { expect { stop }.to_not change { span_op.started? }.from(true) }
        it { expect { stop }.to change { span_op.stopped? }.from(false).to(true) }
        it { expect { stop }.to_not change { span_op.finished? }.from(false) }

        context 'and callbacks have been configured' do
          include_context 'callbacks'
          before { stop }
          it do
            expect(callback_spy).to have_received(:after_stop).with(span_op)
            expect(callback_spy).to_not have_received(:before_start)
            expect(callback_spy).to_not have_received(:after_finish)
          end
        end
      end

      context 'when already stopped' do
        let!(:original_end_time) { span_op.end_time = Time.now }

        it { expect { stop }.to_not change { span_op.start_time }.from(original_end_time) }
        it { expect { stop }.to_not change { span_op.end_time }.from(original_end_time) }
        it { expect { stop }.to_not change { span_op.duration }.from(0) }

        it { expect { stop }.to_not change { span_op.started? }.from(true) }
        it { expect { stop }.to_not change { span_op.stopped? }.from(true) }
        it { expect { stop }.to_not change { span_op.finished? }.from(false) }

        context 'and callbacks have been configured' do
          include_context 'callbacks'
          before { stop }
          it do
            expect(callback_spy).to_not have_received(:after_stop)
            expect(callback_spy).to_not have_received(:before_start)
            expect(callback_spy).to_not have_received(:after_finish)
          end
        end
      end
    end

    context 'given nothing' do
      subject(:stop) { span_op.stop }
      it_behaves_like 'stopped span'
    end

    context 'given nil' do
      subject(:stop) { span_op.stop(nil) }
      it_behaves_like 'stopped span'
    end

    context 'given a Time' do
      subject(:stop) { span_op.stop(end_time) }

      it_behaves_like 'stopped span' do
        let(:end_time) { Datadog::Utils::Time.now.utc }
      end
    end
  end

  describe '#started?' do
    subject(:started?) { span_op.started? }

    context 'when span hasn\'t been started or stopped' do
      it { is_expected.to be false }
    end

    it { expect { span_op.start }.to change { span_op.started? }.from(false).to(true) }
    it { expect { span_op.stop }.to change { span_op.started? }.from(false).to(true) }
    it { expect { span_op.finish }.to change { span_op.started? }.from(false).to(true) }
  end

  describe '#stopped?' do
    subject(:stopped?) { span_op.stopped? }

    context 'when span hasn\'t been started or stopped' do
      it { is_expected.to be false }
    end

    it { expect { span_op.start }.to_not change { span_op.stopped? }.from(false) }
    it { expect { span_op.stop }.to change { span_op.stopped? }.from(false).to(true) }
    it { expect { span_op.finish }.to change { span_op.stopped? }.from(false).to(true) }
  end

  describe '#finish' do
    subject(:finish) { span_op.finish }

    shared_examples 'finished span' do
      let(:end_time) { kind_of(Time) }

      it { expect { finish }.to change { span_op.end_time }.from(nil).to(end_time) }
      it { expect { finish }.to change { span_op.duration }.from(nil).to(kind_of(Float)) }

      context 'and callbacks have been configured' do
        include_context 'callbacks'
        before { finish }
        it do
          expect(callback_spy).to have_received(:after_stop).with(span_op).ordered
          expect(callback_spy).to have_received(:after_finish).with(kind_of(Datadog::Span), span_op).ordered
        end
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
      it { expect { finish }.to change { span_op.end_time }.from(nil).to(kind_of(Time)) }
      it { expect { finish }.to change { span_op.duration }.from(nil).to(0) }
    end

    context 'when already finished' do
      let!(:original_end_time) do
        span_op.start
        @original_span = span_op.finish
        span_op.end_time
      end
      let(:original_span) { @original_span }

      it 'does not overwrite the previous end time' do
        expect(original_end_time).to_not be nil
        expect { finish }.to_not change { span_op.end_time }.from(original_end_time)
      end

      # Expect Span to be memoized
      it 'returns the same Span object' do
        expect(span_op.finish).to be(original_span)
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

  describe '#duration' do
    subject(:duration) { span_op.duration }

    let(:duration_wall_time) { 0.0001 }

    context 'without start or end time provided' do
      let(:static_time) { Time.utc(2010, 9, 15, 22, 3, 15) }

      before do
        # We set the same time no matter what.
        # If duration is greater than zero but start_time == end_time, we can
        # be sure we're using the monotonic time.
        allow(Datadog::Utils::Time).to receive(:now)
          .and_return(static_time)
      end

      it { is_expected.to be nil }

      context 'when started then stopped' do
        before do
          span_op.start
          sleep(0.0002)
          span_op.stop
        end

        it 'uses monotonic time' do
          expect((duration.to_f * 1e9).to_i).to be > 0
          expect(span_op.end_time).to eq static_time
          expect(span_op.start_time).to eq static_time
          expect(span_op.end_time - span_op.start_time).to eq 0
        end
      end
    end

    context 'with start_time provided' do
      # set a start time considerably longer than span duration
      # set a day in the past and then measure duration is longer than
      # amount of time slept, which would represent monotonic
      let!(:start_time) { Time.now - (duration_wall_time * 1e9) }

      it 'does not use monotonic time' do
        span_op.start(start_time)
        sleep(duration_wall_time)
        span_op.stop

        expect(duration).to be_within(1).of(duration_wall_time * 1e9)
      end

      context 'and end_time provided' do
        let(:end_time) { start_time + 123.456 }

        it 'respects the exact times provided' do
          span_op.start(start_time)
          sleep(duration_wall_time)
          span_op.stop(end_time)

          expect(duration).to eq(123.456)
        end
      end
    end

    context 'with end_time provided' do
      # set an end time considerably ahead of than span duration
      # set a day in the future and then measure duration is longer than
      # amount of time slept, which would represent monotonic
      let!(:end_time) { Time.now + (duration_wall_time * 1e9) }

      it 'does not use monotonic time' do
        span_op.start
        sleep(duration_wall_time)
        span_op.stop(end_time)

        expect(duration).to be_within(1).of(duration_wall_time * 1e9)
      end
    end

    context 'with time_provider set' do
      before do
        now = time_now # Expose variable to closure
        Datadog.configure do |c|
          c.time_now_provider = -> { now }
        end
      end

      after { without_warnings { Datadog.configuration.reset! } }

      let(:time_now) { ::Time.utc(2020, 1, 1) }

      it 'sets the start time to the provider time' do
        span_op.start
        span_op.stop

        expect(span_op.start_time).to eq(time_now)
      end
    end
  end

  describe '#allocations' do
    subject(:allocations) { span_op.allocations }

    it { is_expected.to be 0 }

    context 'when span measures an operation' do
      before do
        skip 'Test unstable; improve stability before re-enabling.'
        span_op.measure {}
      end

      it { is_expected.to be > 0 }

      context 'compared to a span that allocates more' do
        let(:span_op_two) { described_class.new('span_op_two') }

        before do
          span_op_two.measure { Object.new }
        end

        it { is_expected.to be < span_op_two.allocations }
      end
    end
  end

  describe '#set_error' do
    subject(:set_error) { span_op.set_error(error) }

    context 'given nil' do
      let(:error) { nil }

      before { set_error }

      it do
        expect(span_op.status).to eq(Datadog::Ext::Errors::STATUS)
        expect(span_op.get_tag(Datadog::Ext::Errors::TYPE)).to be nil
        expect(span_op.get_tag(Datadog::Ext::Errors::MSG)).to be nil
        expect(span_op.get_tag(Datadog::Ext::Errors::STACK)).to be nil
      end
    end

    context 'given an error' do
      let(:error) do
        begin
          raise message
        rescue => e
          e
        end
      end

      let(:message) { 'Test error!' }

      before { set_error }

      it do
        expect(span_op.status).to eq(Datadog::Ext::Errors::STATUS)
        expect(span_op.get_tag(Datadog::Ext::Errors::TYPE)).to eq(error.class.to_s)
        expect(span_op.get_tag(Datadog::Ext::Errors::MSG)).to eq(message)
        expect(span_op.get_tag(Datadog::Ext::Errors::STACK)).to be_a_kind_of(String)
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
