# typed: ignore
require 'spec_helper'
require 'ddtrace/ext/manual_tracing'
require 'ddtrace/span'
require 'ddtrace/utils'

require 'json'
require 'msgpack'

RSpec.describe Datadog::Span do
  subject(:span) { described_class.new(name, **span_options) }

  let(:name) { 'my.span' }
  let(:span_options) { {} }

  before do
    Datadog.configure
  end

  after do
    without_warnings { Datadog.configuration.reset! }
  end

  describe '#initialize' do
    context 'resource' do
      context 'with no value provided' do
        it 'defaults to name' do
          expect(span.resource).to eq(name)
        end
      end

      context 'with nil' do
        let(:span_options) { { resource: nil } }

        it 'respects the explicitly provided nil' do
          expect(span.resource).to be_nil
        end
      end

      context 'with a value' do
        let(:span_options) { { resource: 'my resource' } }

        it 'honors provided value' do
          expect(span.resource).to eq('my resource')
        end
      end
    end
  end

  context 'ids' do
    it do
      expect(span.span_id).to be_nonzero
      expect(span.parent_id).to be_zero
      expect(span.trace_id).to be_nonzero

      expect(span.trace_id).to_not eq(span.span_id)
    end

    context 'with parent id' do
      let(:span_options) { { parent_id: 2 } }

      it { expect(span.parent_id).to eq(2) }
    end

    context 'with trace id' do
      let(:span_options) { { trace_id: 3 } }

      it { expect(span.trace_id).to eq(3) }
    end
  end

  describe '#stop' do
    subject(:stop) { span.stop }

    it 'calculates duration' do
      expect(span.start_time).to be_nil
      expect(span.end_time).to be_nil

      subject

      expect(span.end_time).to be <= Time.now
      expect(span.start_time).to be <= span.end_time
      expect(span.to_hash[:duration]).to be >= 0
    end

    context 'with multiple calls to stop' do
      it 'does not flush the span more than once' do
        subject
        expect(span.stop).to be_falsey
      end

      it 'does not modify the span' do
        end_time = subject.end_time

        expect(span.stop).to be_falsey
        expect(span.end_time).to eq(end_time)
      end
    end

    context 'with stop time provided' do
      subject(:stop) { span.stop(time) }

      let(:time) { Time.now }

      it 'does not use wall time' do
        sleep(0.0001)
        subject

        expect(span.end_time).to eq(time)
      end
    end

    describe '#stopped?' do
      it { expect { subject }.to change { span.stopped? }.from(false).to(true) }
    end

    # DEPRECATED: Use #stopped? instead.
    describe '#finished?' do
      it { expect { subject }.to change { span.finished? }.from(false).to(true) }
    end

    context 'when service' do
      subject(:service) do
        stop
        span.service
      end

      context 'is set' do
        let(:service_value) { 'span-service' }
        before { span.service = service_value }
        it { is_expected.to eq service_value }
      end
    end
  end

  describe '#duration' do
    subject(:duration) { span.duration }

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

      it 'uses monotonic time' do
        span.start
        sleep(0.0002)
        span.stop
        expect((subject.to_f * 1e9).to_i).to be > 0

        expect(span.end_time).to eq static_time
        expect(span.start_time).to eq static_time
        expect(span.end_time - span.start_time).to eq 0
      end
    end

    context 'with start_time provided' do
      # set a start time considerably longer than span duration
      # set a day in the past and then measure duration is longer than
      # amount of time slept, which would represent monotonic
      let!(:start_time) { Time.now - (duration_wall_time * 1e9) }

      it 'does not use monotonic time' do
        span.start(start_time)
        sleep(duration_wall_time)
        span.stop

        expect(subject).to be_within(1).of(duration_wall_time * 1e9)
      end

      context 'and end_time provided' do
        let(:end_time) { start_time + 123.456 }

        it 'respects the exact times provided' do
          span.start(start_time)
          sleep(duration_wall_time)
          span.stop(end_time)

          expect(subject).to eq(123.456)
        end
      end
    end

    context 'with end_time provided' do
      # set an end time considerably ahead of than span duration
      # set a day in the future and then measure duration is longer than
      # amount of time slept, which would represent monotonic
      let!(:end_time) { Time.now + (duration_wall_time * 1e9) }

      it 'does not use monotonic time' do
        span.start
        sleep(duration_wall_time)
        span.stop(end_time)

        expect(subject).to be_within(1).of(duration_wall_time * 1e9)
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
        span.start
        span.stop

        expect(span.start_time).to eq(time_now)
      end
    end
  end

  describe '#to_hash' do
    subject(:to_hash) { span.to_hash }

    let(:span_options) { { trace_id: 12 } }

    before { span.span_id = 34 }

    it do
      is_expected.to eq(
        trace_id: 12,
        span_id: 34,
        parent_id: 0,
        name: 'my.span',
        service: nil,
        resource: 'my.span',
        type: nil,
        meta: {},
        metrics: {},
        allocations: 0,
        error: 0
      )
    end

    context 'with a stopped span' do
      before { span.stop }

      it 'includes timing information' do
        is_expected.to include(
          start: be >= 0,
          duration: be >= 0
        )
      end
    end
  end

  describe '#to_msgpack' do
    subject(:to_msgpack) { MessagePack.unpack(MessagePack.pack(span)) }

    it 'correctly performs a serialization round-trip' do
      is_expected.to eq(Hash[span.to_hash.map { |k, v| [k.to_s, v] }])
    end
  end

  describe '#to_json' do
    subject(:to_json) { JSON(JSON.dump(span)) }

    it 'correctly performs a serialization round-trip' do
      is_expected.to eq(Hash[span.to_hash.map { |k, v| [k.to_s, v] }])
    end
  end

  describe '#pretty_print' do
    subject(:pretty_print) { PP.pp(span) }

    it 'output without errors' do
      expect { pretty_print }.to output.to_stdout
    end
  end
end
