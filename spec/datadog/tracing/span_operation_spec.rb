require 'spec_helper'

require 'securerandom'
require 'time'

require 'datadog/core'
require 'datadog/core/logger'

require 'datadog/tracing/metadata/ext'
require 'datadog/tracing/span_operation'
require 'datadog/tracing/span_link'
require 'datadog/tracing/trace_digest'
require 'datadog/tracing/span'
require 'datadog/tracing/utils'

RSpec.describe Datadog::Tracing::SpanOperation do
  subject(:span_op) { described_class.new(name, **options) }
  let(:name) { 'my.operation' }
  let(:options) { {} }

  shared_examples 'a root span operation' do
    it do
      is_expected.to have_attributes(
        parent_id: 0
      )
    end
  end

  shared_examples 'a child span operation' do
    it 'associates to the parent' do
      expect(span_op).to have_attributes(
        parent_id: parent.id,
        trace_id: parent.trace_id
      )
    end
  end

  shared_context 'parent span operation' do
    let(:parent) { described_class.new('parent', service: parent_service) }
    let(:parent_service) { instance_double(String) }
  end

  shared_context 'callbacks' do
    let(:callback_spy) { spy('callback spy') }

    before do
      events = span_op.send(:events)

      # after_finish
      allow(callback_spy).to receive(:after_finish)
      events.after_finish.subscribe do |*args|
        callback_spy.after_finish(*args)
      end

      # after_stop
      allow(callback_spy).to receive(:after_stop)
      events.after_stop.subscribe do |*args|
        callback_spy.after_stop(*args)
      end

      # before_start
      allow(callback_spy).to receive(:before_start)
      events.before_start.subscribe do |*args|
        callback_spy.before_start(*args)
      end

      # on_error
      allow(callback_spy).to receive(:on_error)
      events.on_error.wrap_default do |*args|
        callback_spy.on_error(*args)
      end
    end
  end

  describe '::new' do
    context 'given only a name' do
      it 'has default attributes' do
        is_expected.to have_attributes(
          end_time: nil,
          id: kind_of(Integer),
          name: name,
          parent_id: 0,
          resource: name,
          service: nil,
          start_time: nil,
          status: 0,
          trace_id: kind_of(Integer),
          type: nil,
          links: []
        )
      end

      it 'has default behavior' do
        is_expected.to have_attributes(
          duration: nil,
          finished?: false,
          started?: false,
          stopped?: false
        )
      end

      it_behaves_like 'a root span operation'
    end

    context 'given an option' do
      shared_examples 'a string property' do |nillable: true|
        let(:options) { { property => value } }

        context 'set to a String' do
          let(:value) { 'test string' }
          it { is_expected.to have_attributes(property => value) }
        end

        context 'set to a non-UTF-8 String' do
          let(:value) { 'ascii'.encode(Encoding::ASCII) }
          it { is_expected.to have_attributes(property => value) }
          it { expect(span_op.public_send(property).encoding).to eq(Encoding::UTF_8) }
        end

        context 'invoking the public setter' do
          subject! { span_op.public_send("#{property}=", value) }

          context 'with a string' do
            let(:value) { 'test string' }
            it { expect(span_op).to have_attributes(property => value) }
          end

          context 'with a string that is not in UTF-8' do
            let(:value) { 'ascii'.encode(Encoding::ASCII) }
            it { expect(span_op).to have_attributes(property => value) }
            it { expect(span_op.public_send(property).encoding).to eq(Encoding::UTF_8) }
          end
        end

        if nillable
          context 'set to nil' do
            let(:value) { nil }
            # Allow property to be explicitly set to nil
            it { is_expected.to have_attributes(property => nil) }
          end
        else
          context 'set to nil' do
            let(:value) { nil }
            it { expect { subject }.to raise_error(ArgumentError) }
          end
        end
      end

      context ':on_error' do
        let(:options) { { on_error: on_error } }

        let(:block) { proc { raise error } }
        let(:error) { error_class.new('error message') }
        let(:error_class) { stub_const('TestError', Class.new(StandardError)) }

        context 'that is nil' do
          let(:on_error) { nil }

          context 'and #measure raises an error' do
            subject(:measure) { span_op.measure { raise error } }

            before { allow(span_op).to receive(:set_error) }

            it 'propagates the error' do
              expect(Datadog.logger).not_to receive(:warn)
              expect { measure }.to raise_error(error)
              expect(span_op).to have_received(:set_error).with(error)
            end
          end
        end

        context 'that is a block' do
          let(:on_error) { block }

          it 'yields to the error block and raises the error' do
            expect(Datadog.logger).not_to receive(:warn)
            expect do
              expect do |b|
                options[:on_error] = b.to_proc
                span_op.measure(&block)
              end.to yield_with_args(
                a_kind_of(described_class),
                error
              )
            end.to raise_error(error)

            # It should not set an error, as this overrides behavior.
            expect(span_op).to_not have_error
          end
        end

        context 'that is not a Proc' do
          let(:on_error) { 'not a proc' }

          it 'fallbacks to default error handler and log a debug message' do
            expect(Datadog.logger).to receive(:warn).with(
              /on_error argument to SpanOperation ignored because is not a Proc: not a proc/
            )
            expect do
              span_op.measure(&block)
            end.to raise_error(error)
          end
        end
      end

      describe ':name' do
        it_behaves_like 'a string property', nillable: false do
          let(:property) { :name }

          # :name is not a keyword argument, but positional.
          # We swap those two here.
          let(:options) { {} }
          let(:name) { value }
        end
      end

      describe ':parent_id' do
        let(:options) { { parent_id: parent_id } }

        context 'that is nil' do
          let(:parent_id) { nil }
          it { is_expected.to have_attributes(parent_id: 0) }
        end

        context 'that is an Integer' do
          let(:parent_id) { instance_double(Integer) }
          it { is_expected.to have_attributes(parent_id: parent_id) }
        end
      end

      describe ':id' do
        let(:options) { { id: id } }

        context 'that is nil' do
          let(:id) { nil }
          it { is_expected.to have_attributes(id: kind_of(Integer)) }
        end

        context 'that is an Integer' do
          let(:id) { instance_double(Integer) }
          it { is_expected.to have_attributes(id: id) }
        end
      end

      describe ':resource' do
        it_behaves_like 'a string property' do
          let(:property) { :resource }
        end
      end

      describe ':service' do
        it_behaves_like 'a string property' do
          let(:property) { :service }
        end
      end

      describe ':links' do
        let(:options) { { links: span_links } }

        context 'that is an Array' do
          let(:span_links) do
            [Datadog::Tracing::SpanLink.new(
              Datadog::Tracing::TraceDigest.new(trace_id: 1, span_id: 2),
              attributes: { "link.name": 'moon' }
            )]
          end
          it { is_expected.to have_attributes(links: span_links) }
        end

        context 'that is nil' do
          let(:span_links) { nil }
          it { is_expected.to have_attributes(links: []) }
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

          it_behaves_like 'a root span operation'
        end

        context 'that is a Hash' do
          let(:tags) { { 'custom_tag' => 'custom_value' } }

          it_behaves_like 'a root span operation'
          it { expect(span_op.get_tag('custom_tag')).to eq(tags['custom_tag']) }
        end
      end

      describe ':trace_id' do
        let(:options) { { trace_id: trace_id } }

        context 'that is nil' do
          let(:trace_id) { nil }
          it { is_expected.to have_attributes(trace_id: kind_of(Integer)) }
        end

        context 'that is an Integer' do
          let(:trace_id) { Datadog::Tracing::Utils::TraceId.next_id }
          it { is_expected.to have_attributes(trace_id: trace_id) }
        end
      end

      describe ':type' do
        it_behaves_like 'a string property' do
          let(:property) { :type }
        end
      end
    end
  end

  describe '#resource=' do
    subject!(:resource=) { span_op.resource = resource }

    context 'with a string that is not in UTF-8' do
      let(:resource) { 'legacy'.encode(Encoding::ASCII) }
      it { expect(span_op.resource).to eq(resource) }
      it { expect(span_op.resource.encoding).to eq(Encoding::UTF_8) }
    end
  end

  describe '#measure' do
    subject(:measure) { span_op.measure(&block) }

    let(:block) do
      allow(block_spy).to receive(:measure).and_return(return_value)
      proc { |op| block_spy.measure(op) }
    end

    let(:return_value) { SecureRandom.uuid }
    let(:block_spy) { spy('block') }

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
          expect(callback_spy).to have_received(:after_stop).with(span_op, nil).ordered
          expect(callback_spy).to have_received(:after_finish).with(kind_of(Datadog::Tracing::Span), span_op).ordered
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
      it { expect { measure }.to raise_error(Datadog::Tracing::SpanOperation::AlreadyStartedError) }
    end

    context 'when the operation has already been started' do
      before { span_op.start }
      it { expect { measure }.to raise_error(Datadog::Tracing::SpanOperation::AlreadyStartedError) }
    end

    context 'when the operation has already been finished' do
      before { span_op.finish }
      it { expect { measure }.to raise_error(Datadog::Tracing::SpanOperation::AlreadyStartedError) }
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
          expect(callback_spy).to have_received(:after_stop).with(span_op, error).ordered
          expect(callback_spy).to have_received(:on_error).with(span_op, error).ordered
          expect(callback_spy).to have_received(:after_finish).with(kind_of(Datadog::Tracing::Span), span_op).ordered
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
          expect(callback_spy).to have_received(:after_stop).with(span_op, error).ordered
          expect(callback_spy).to have_received(:on_error).with(span_op, error).ordered
          expect(callback_spy).to have_received(:after_finish).with(kind_of(Datadog::Tracing::Span), span_op).ordered
        end
      end
    end

    context 'identifying service_entry_span' do
      context 'when service of root and child are `nil`' do
        it do
          root_span_op = described_class.new('root')
          child_span_op = described_class.new('child_1')
          child_span_op.send(:parent=, root_span_op)

          root_span_op.measure do
            child_span_op.measure do
              # Do stuff
            end
          end

          root_span = root_span_op.finish
          child_span = child_span_op.finish

          expect(root_span.__send__(:service_entry?)).to be true
          expect(child_span.__send__(:service_entry?)).to be false
        end
      end

      context 'when service of root and child are identical' do
        it do
          root_span_op = described_class.new('root', service: 'root_service')
          child_span_op = described_class.new('child_1', service: root_span_op.service)
          child_span_op.send(:parent=, root_span_op)

          root_span_op.measure do
            child_span_op.measure do
              # Do stuff
            end
          end

          root_span = root_span_op.finish
          child_span = child_span_op.finish

          expect(root_span.__send__(:service_entry?)).to be true
          expect(child_span.__send__(:service_entry?)).to be false
        end
      end

      context 'when service of root and child are different' do
        it do
          root_span_op = described_class.new('root')
          child_span_op = described_class.new('child_1', service: 'child_service')
          child_span_op.send(:parent=, root_span_op)

          root_span_op.measure do
            child_span_op.measure do
              # Do stuff
            end
          end

          root_span = root_span_op.finish
          child_span = child_span_op.finish

          expect(root_span.__send__(:service_entry?)).to be true
          expect(child_span.__send__(:service_entry?)).to be true
        end
      end

      context 'when service of root and child are different, overriden within the measure block' do
        it do
          root_span_op = described_class.new('root')
          child_span_op = described_class.new('child_1')
          child_span_op.send(:parent=, root_span_op)

          root_span_op.measure do
            child_span_op.measure do |span_op|
              span_op.service = 'child_service'

              # Do stuff
            end
          end

          root_span = root_span_op.finish
          child_span = child_span_op.finish

          expect(root_span.__send__(:service_entry?)).to be true
          expect(child_span.__send__(:service_entry?)).to be true
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
      let(:start_time) { Datadog::Core::Utils::Time.now.utc }

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
            expect(callback_spy).to have_received(:after_stop).with(span_op, nil)
            expect(callback_spy).to have_received(:before_start).with(span_op)
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
            expect(callback_spy).to have_received(:after_stop).with(span_op, nil)
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
        let(:end_time) { Datadog::Core::Utils::Time.now.utc }
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
          expect(callback_spy).to have_received(:after_stop).with(span_op, nil).ordered
          expect(callback_spy).to have_received(:after_finish).with(kind_of(Datadog::Tracing::Span), span_op).ordered
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
        let(:end_time) { Datadog::Core::Utils::Time.now.utc }
        before { span_op.start }
      end
    end

    context 'when not started' do
      it { expect { finish }.to change { span_op.end_time }.from(nil).to(kind_of(Time)) }
      # Will be a float, not 0 time, because "duration" is used, not time stamps.
      it { expect { finish }.to change { span_op.duration }.from(nil).to(kind_of(Float)) }
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
        allow(Datadog::Core::Utils::Time).to receive(:now)
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

      context 'with get_time_provider set' do
        let(:clock_increment) { 0.42 }
        before do
          incr = clock_increment
          clock_time = clock_increment
          Datadog.configure do |c|
            # Use a custom clock provider that increments by `clock_increment`
            c.get_time_provider = ->(_unit = :float_second) { clock_time += incr }
          end
        end

        after { without_warnings { Datadog.configuration.reset! } }

        it 'sets the duration to the provider increment' do
          span_op.start
          span_op.stop

          expect(span_op.duration).to be_within(0.01).of(clock_increment)
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

  describe '#set_error' do
    subject(:set_error) { span_op.set_error(error) }

    context 'given nil' do
      let(:error) { nil }

      before { set_error }

      it do
        expect(span_op.status).to eq(Datadog::Tracing::Metadata::Ext::Errors::STATUS)
        expect(span_op.get_tag(Datadog::Tracing::Metadata::Ext::Errors::TAG_TYPE)).to be nil
        expect(span_op.get_tag(Datadog::Tracing::Metadata::Ext::Errors::TAG_MSG)).to be nil
        expect(span_op.get_tag(Datadog::Tracing::Metadata::Ext::Errors::TAG_STACK)).to be nil
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
        expect(span_op.status).to eq(Datadog::Tracing::Metadata::Ext::Errors::STATUS)
        expect(span_op.get_tag(Datadog::Tracing::Metadata::Ext::Errors::TAG_TYPE)).to eq(error.class.to_s)
        expect(span_op.get_tag(Datadog::Tracing::Metadata::Ext::Errors::TAG_MSG)).to eq(message)
        expect(span_op.get_tag(Datadog::Tracing::Metadata::Ext::Errors::TAG_STACK)).to be_a_kind_of(String)
      end
    end
  end

  describe '#record_exception' do
    let(:error) { StandardError.new('test error').tap { |e| e.set_backtrace(['this is a backtrace']) } }

    it 'creates a span event' do
      span_op.record_exception(error)
      span_op.record_exception(error)

      expect(span_op.span_events.length).to eq(2)
      expect(span_op.span_events[0]).to have_attributes(
        name: 'exception',
        attributes: {
          'exception.type' => 'StandardError',
          'exception.message' => 'test error',
          'exception.stacktrace' => 'this is a backtrace: test error (StandardError)
',
        }
      )
      expect(span_op.span_events[1]).to have_attributes(
        name: 'exception',
        attributes: {
          'exception.type' => 'StandardError',
          'exception.message' => 'test error',
          'exception.stacktrace' => 'this is a backtrace: test error (StandardError)
',
        }
      )
    end

    it 'provides custom attributes' do
      span_op.record_exception(
        error,
        attributes: { 'custom_attr1' => 'value',
                      custom_attr2: 'value' }
      )

      expect(span_op.span_events.last).to have_attributes(
        name: 'exception',
        attributes: {
          'exception.type' => 'StandardError',
          'exception.message' => 'test error',
          'exception.stacktrace' => 'this is a backtrace: test error (StandardError)
',
          'custom_attr1' => 'value',
          'custom_attr2' => 'value'
        }
      )
    end

    it 'provides invalid custom attributes' do
      allow(Datadog.logger).to receive(:warn)

      span_op.record_exception(
        error,
        attributes: {
          'custom_attr' => 'value',
          'custom_attr2' => { foo: 'bar' },
          'custom_attr3' => [[1]],
          'custom_attr4' => [1, 'foo'],
          'custom_attr5' => 2 << 65,
          'custom_attr6' => -2 << 65,
          'custom_attr7' => Float::NAN,
          'custom_attr8' => Float::INFINITY
        }
      )

      expect(span_op.span_events[0].attributes.keys.length).to eq(4)
      expect(span_op.span_events[0]).to have_attributes(
        name: 'exception',
        attributes: {
          'exception.type' => 'StandardError',
          'exception.message' => 'test error',
          'exception.stacktrace' => 'this is a backtrace: test error (StandardError)
',
          'custom_attr' => 'value'
        }
      )
      expect(Datadog.logger).to have_received(:warn).with(
        /Attribute custom_attr2 must be a string, number, boolean, or array: \{.*foo.*bar.*\}./
      )
      expect(Datadog.logger).to have_received(:warn).with(
        'Attribute custom_attr3 must be a string, number, or boolean: [[1]].'
      )
      expect(Datadog.logger).to have_received(:warn).with('Attribute custom_attr4 array must be homogenous: [1, "foo"].')
      expect(Datadog.logger).to have_received(:warn).with(
        "Attribute custom_attr5 must be within the range of a signed 64-bit integer: #{2 << 65}."
      )
      expect(Datadog.logger).to have_received(:warn).with(
        "Attribute custom_attr6 must be within the range of a signed 64-bit integer: #{-(2 << 65)}."
      )
      expect(Datadog.logger).to have_received(:warn).with('Attribute custom_attr7 must be a finite number: NaN.')
      expect(Datadog.logger).to have_received(:warn).with('Attribute custom_attr8 must be a finite number: Infinity.')
    end
  end
end

RSpec.describe Datadog::Tracing::SpanOperation::Events do
  subject(:events) { described_class.new }

  describe '::new' do
    it {
      is_expected.to have_attributes(
        after_finish: kind_of(described_class::AfterFinish),
        before_start: kind_of(described_class::BeforeStart),
        on_error: kind_of(described_class::OnError)
      )
    }
  end

  describe '#after_finish' do
    subject(:after_finish) { events.after_finish }
    it { is_expected.to be_a_kind_of(Datadog::Tracing::Event) }
    it { expect(after_finish.name).to be(:after_finish) }
  end

  describe '#before_start' do
    subject(:before_start) { events.before_start }
    it { is_expected.to be_a_kind_of(Datadog::Tracing::Event) }
    it { expect(before_start.name).to be(:before_start) }
  end

  describe '#on_error' do
    subject(:on_error) { events.on_error }
    it { is_expected.to respond_to(:publish) }
  end
end
