# typed: ignore
require 'spec_helper'
require 'ddtrace/ext/forced_tracing'
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

    context 'set parent span' do
      subject(:parent=) { span.parent = parent }

      context 'to a span' do
        let(:parent) { described_class.new('parent', **parent_span_options) }
        let(:parent_span_options) { {} }

        before do
          parent.sampled = false
          subject
        end

        it do
          expect(span.parent).to eq(parent)
          expect(span.parent_id).to eq(parent.span_id)
          expect(span.trace_id).to eq(parent.trace_id)
          expect(span.sampled).to eq(false)
        end

        context 'with service' do
          let(:parent_span_options) { { service: 'parent' } }

          it 'copies parent service to child' do
            expect(span.service).to eq('parent')
          end

          context 'with existing child service' do
            let(:span_options) { { service: 'child' } }

            it 'does not override child service' do
              expect(span.service).to eq('child')
            end
          end
        end
      end

      context 'to nil' do
        let(:parent) { nil }

        it 'removes the parent' do
          subject
          expect(span.parent).to be_nil
          expect(span.parent_id).to be_zero
          expect(span.trace_id).to eq(span.span_id)
        end
      end
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

  describe '#clear_tag' do
    subject(:clear_tag) { span.clear_tag(key) }

    let(:key) { 'key' }
    let(:value) { 'value' }

    before { span.set_tag(key, value) }

    it do
      expect { subject }.to change { span.get_tag(key) }.from(value).to(nil)
    end

    it 'removes value, instead of setting to nil, to ensure correct deserialization by agent' do
      subject
      expect(span.instance_variable_get(:@meta)).to_not have_key(key)
    end
  end

  describe '#clear_metric' do
    subject(:clear_metric) { span.clear_metric(key) }

    let(:key) { 'key' }
    let(:value) { 1.0 }

    before { span.set_metric(key, value) }

    it do
      expect { subject }.to change { span.get_metric(key) }.from(value).to(nil)
    end

    it 'removes value, instead of setting to nil, to ensure correct deserialization by agent' do
      subject
      expect(span.instance_variable_get(:@metrics)).to_not have_key(key)
    end
  end

  describe '#get_metric' do
    subject(:get_metric) { span.get_metric(key) }

    let(:key) { 'key' }

    context 'with no metrics' do
      it { is_expected.to be_nil }
    end

    context 'with a metric' do
      let(:value) { 1.0 }

      before { span.set_metric(key, value) }

      it { is_expected.to eq(1.0) }
    end

    context 'with a tag' do
      let(:value) { 'tag' }

      before { span.set_tag(key, value) }

      it { is_expected.to eq('tag') }
    end
  end

  describe '#set_metric' do
    subject(:set_metric) { span.set_metric(key, value) }

    let(:key) { 'key' }

    let(:metrics) { span.to_hash[:metrics] }
    let(:metric) { metrics[key] }

    shared_examples 'a metric' do |value, expected|
      let(:value) { value }

      it do
        subject
        expect(metric).to eq(expected)
      end
    end

    context 'with a valid value' do
      context 'with an integer' do
        it_behaves_like 'a metric', 0, 0.0
      end

      context 'with a float' do
        it_behaves_like 'a metric', 12.34, 12.34
      end

      context 'with a number as string' do
        it_behaves_like 'a metric', '12.34', 12.34
      end
    end

    context 'with an invalid value' do
      context 'with nil' do
        it_behaves_like 'a metric', nil, nil
      end

      context 'with a string' do
        it_behaves_like 'a metric', 'foo', nil
      end

      context 'with a complex object' do
        it_behaves_like 'a metric', [], nil
      end
    end
  end

  describe '#set_tag' do
    subject(:set_tag) { span.set_tag(key, value) }

    shared_examples_for 'meta tag' do
      let(:old_value) { nil }

      it 'sets a tag' do
        expect { set_tag }.to change { span.instance_variable_get(:@meta)[key] }
          .from(old_value)
          .to(value.to_s)
      end

      it 'does not set a metric' do
        expect { set_tag }.to_not change { span.instance_variable_get(:@metrics)[key] }
          .from(old_value)
      end
    end

    shared_examples_for 'metric tag' do
      let(:old_value) { nil }

      it 'does not set a tag' do
        expect { set_tag }.to_not change { span.instance_variable_get(:@meta)[key] }
          .from(old_value)
      end

      it 'sets a metric' do
        expect { set_tag }.to change { span.instance_variable_get(:@metrics)[key] }
          .from(old_value)
          .to(value.to_f)
      end
    end

    context 'given _dd.hostname' do
      let(:key) { '_dd.hostname' }
      let(:value) { 1 }

      it_behaves_like 'meta tag'
    end

    context 'given _dd.origin' do
      let(:key) { '_dd.origin' }
      let(:value) { 2 }

      it_behaves_like 'meta tag'
    end

    context 'given http.status_code' do
      let(:key) { 'http.status_code' }
      let(:value) { 200 }

      it_behaves_like 'meta tag'
    end

    context 'given version' do
      let(:key) { 'version' }
      let(:value) { 3 }

      it_behaves_like 'meta tag'
    end

    context 'given a numeric tag' do
      let(:key) { 'system.pid' }
      let(:value) { 123 }

      context 'which is an integer' do
        context 'that exceeds the upper limit' do
          let(:value) { described_class::NUMERIC_TAG_SIZE_RANGE.max.to_i + 1 }

          it_behaves_like 'meta tag'
        end

        context 'at the upper limit' do
          let(:value) { described_class::NUMERIC_TAG_SIZE_RANGE.max.to_i }

          it_behaves_like 'metric tag'
        end

        context 'at the lower limit' do
          let(:value) { described_class::NUMERIC_TAG_SIZE_RANGE.min.to_i }

          it_behaves_like 'metric tag'
        end

        context 'that is below the lower limit' do
          let(:value) { described_class::NUMERIC_TAG_SIZE_RANGE.min.to_i - 1 }

          it_behaves_like 'meta tag'
        end
      end

      context 'which is a float' do
        context 'that exceeds the upper limit' do
          let(:value) { described_class::NUMERIC_TAG_SIZE_RANGE.max.to_f + 1.0 }

          it_behaves_like 'metric tag'
        end

        context 'at the upper limit' do
          let(:value) { described_class::NUMERIC_TAG_SIZE_RANGE.max.to_f }

          it_behaves_like 'metric tag'
        end

        context 'at the lower limit' do
          let(:value) { described_class::NUMERIC_TAG_SIZE_RANGE.min.to_f }

          it_behaves_like 'metric tag'
        end

        context 'that is below the lower limit' do
          let(:value) { described_class::NUMERIC_TAG_SIZE_RANGE.min.to_f - 1.0 }

          it_behaves_like 'metric tag'
        end
      end

      context 'that conflicts with an existing tag' do
        before { span.set_tag(key, 'old value') }

        it 'removes the tag' do
          expect { set_tag }.to change { span.instance_variable_get(:@meta)[key] }
            .from('old value')
            .to(nil)
        end

        it 'adds a new metric' do
          expect { set_tag }.to change { span.instance_variable_get(:@metrics)[key] }
            .from(nil)
            .to(value)
        end
      end

      context 'that conflicts with an existing metric' do
        before { span.set_metric(key, 404) }

        it 'replaces the metric' do
          expect { set_tag }.to change { span.instance_variable_get(:@metrics)[key] }
            .from(404)
            .to(value)

          expect(span.instance_variable_get(:@meta)[key]).to be nil
        end
      end
    end

    # context 'that conflicts with a metric' do
    #   it 'removes the metric'
    #   it 'adds a new tag'
    # end

    context 'given Datadog::Ext::Analytics::TAG_ENABLED' do
      let(:key) { Datadog::Ext::Analytics::TAG_ENABLED }
      let(:value) { true }

      before { set_tag }

      it 'sets the analytics sample rate' do
        # Both should return the same tag
        expect(span.get_metric(Datadog::Ext::Analytics::TAG_SAMPLE_RATE)).to eq(1.0)
        expect(span.get_tag(Datadog::Ext::Analytics::TAG_SAMPLE_RATE)).to eq(1.0)
      end
    end

    context 'given Datadog::Ext::Analytics::TAG_SAMPLE_RATE' do
      let(:key) { Datadog::Ext::Analytics::TAG_SAMPLE_RATE }
      let(:value) { 0.5 }

      before { set_tag }

      it 'sets the analytics sample rate' do
        # Both should return the same tag
        expect(span.get_metric(Datadog::Ext::Analytics::TAG_SAMPLE_RATE)).to eq(value)
        expect(span.get_tag(Datadog::Ext::Analytics::TAG_SAMPLE_RATE)).to be value
      end
    end
  end

  describe '#set_tags' do
    subject(:set_tags) { span.set_tags(tags) }

    context 'with empty hash' do
      let(:tags) { {} }

      it 'does not change tags' do
        expect(span).to_not receive(:set_tag)
        expect { set_tags }.to_not change { span.instance_variable_get(:@meta) }.from({})
      end
    end

    context 'with multiple tags' do
      let(:tags) { { 'user.id' => 123, 'user.domain' => 'datadog.com' } }

      it 'sets the tags from hash keys' do
        expect { set_tags }.to change { tags.map { |k, _| span.get_tag(k) } }.from([nil, nil]).to([123, 'datadog.com'])
      end
    end

    context 'with nested hashes' do
      let(:tags) do
        {
          'user' => {
            'id' => 123
          }
        }
      end

      it 'does not support it - it sets stringified nested hash as value' do
        expect { set_tags }.to change { span.get_tag('user') }.from(nil).to('{"id"=>123}')
      end
    end
  end

  describe '#set_error' do
    subject(:set_error) { span.set_error(error) }

    let(:error) { RuntimeError.new('oops') }
    let(:backtrace) { %w[method1 method2 method3] }

    before { error.set_backtrace(backtrace) }

    it do
      subject

      expect(span).to have_error
      expect(span).to have_error_message('oops')
      expect(span).to have_error_type('RuntimeError')
      backtrace.each do |method|
        expect(span).to have_error_stack(include(method))
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
