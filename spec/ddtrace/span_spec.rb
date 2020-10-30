require 'spec_helper'
require 'ddtrace/ext/forced_tracing'
require 'ddtrace/span'
require 'ddtrace/utils'

require 'json'
require 'msgpack'

RSpec.describe Datadog::Span do
  subject(:span) { described_class.new(tracer, name, context: context, **span_options) }
  let(:tracer) { get_test_tracer }
  let(:context) { Datadog::Context.new }
  let(:name) { 'my.span' }
  let(:span_options) { {} }

  before(:each) do
    Datadog.configure
  end

  after(:each) do
    Datadog.configuration.reset!
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
        let(:parent) { described_class.new(tracer, 'parent', **parent_span_options) }
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

  describe '#finish' do
    subject(:finish) { span.finish }

    it 'calculates duration' do
      expect(span.start_time).to be_nil
      expect(span.end_time).to be_nil

      subject

      expect(span.end_time).to be <= Time.now
      expect(span.start_time).to be <= span.end_time
      expect(span.to_hash[:duration]).to be >= 0
    end

    context 'with multiple calls to finish' do
      it 'does not flush the span more than once' do
        allow(context).to receive(:close_span).once
        allow(tracer).to receive(:record).once

        subject
        expect(span.finish).to be_falsey
      end

      it 'does not modify the span' do
        end_time = subject.end_time

        expect(span.finish).to be_falsey
        expect(span.end_time).to eq(end_time)
      end
    end

    context 'with finish time provided' do
      subject(:finish) { span.finish(time) }
      let(:time) { Time.now }

      it 'does not use wall time' do
        sleep(0.0001)
        subject

        expect(span.end_time).to eq(time)
      end
    end

    context '#finished?' do
      it { expect { subject }.to change { span.finished? }.from(false).to(true) }
    end

    context 'when an error occurs while closing the span on the context' do
      include_context 'health metrics'

      let(:error) { error_class.new }
      let(:error_class) { stub_const('SpanCloseError', Class.new(StandardError)) }

      RSpec::Matchers.define :a_record_finish_error do |error|
        match { |actual| actual == "error recording finished trace: #{error}" }
      end

      before do
        allow(Datadog.logger).to receive(:debug)
        allow(context).to receive(:close_span)
          .with(span)
          .and_raise(error)
        finish
      end

      it 'logs a debug message' do
        expect(Datadog.logger).to have_received(:debug)
          .with(a_record_finish_error(error))
      end

      it 'sends a span finish error metric' do
        expect(health_metrics).to have_received(:error_span_finish)
          .with(1, tags: ["error:#{error_class.name}"])
      end
    end

    context 'when service' do
      subject(:service) do
        finish
        span.service
      end

      context 'is set' do
        let(:service_value) { 'span-service' }
        before { span.service = service_value }
        it { is_expected.to eq service_value }
      end

      context 'is not set' do
        let(:default_service) { 'default-service' }
        before { allow(tracer).to receive(:default_service).and_return(default_service) }
        it { is_expected.to eq default_service }
      end
    end
  end

  describe '#duration' do
    subject(:duration) { span.duration }

    context 'without start or end time provided' do
      let(:static_time) { Time.new('2010-09-16 00:03:15 +0200') }

      before do
        # We set the same time no matter what.
        # If duration is greater than zero but start_time == end_time, we can
        # be sure we're using the monotonic time.
        allow(::Time).to receive(:now)
          .and_return(static_time)

        allow(Datadog::Utils::Time).to receive(:current_time)
          .and_return(static_time)
      end

      it 'uses monotonic time' do
        if Gem::Version.new(RUBY_VERSION) < Gem::Version.new('2.1.0')
          skip('monotonic time not supported')
        else
          span.start
          sleep(0.0002)
          span.finish
          expect((subject.to_f * 1e9).to_i).to be > 0

          expect(span.end_time).to eq static_time
          expect(span.start_time).to eq static_time
          expect(span.end_time - span.start_time).to eq 0
        end
      end
    end

    context 'with start_time provided' do
      # set a start time considerably longer than span duration
      # set a day in the past and then measure duration is longer than
      # amount of time slept, which would represent monotonic
      let(:start_time) { Time.now - (3600 * 24) }

      it 'does not use monotonic time' do
        span.start(start_time)
        sleep(0.0001)
        span.finish

        expect((subject.to_f * 1e9).to_i).to be >= 1e9
      end
    end

    context 'with end_time provided' do
      # set an end time considerably ahead of than span duration
      # set a day in the future and then measure duration is longer than
      # amount of time slept, which would represent monotonic
      let(:end_time) { Time.now + (3600 * 24) }

      it 'does not use monotonic time' do
        span.start
        sleep(0.0001)
        span.finish(end_time)

        expect((subject.to_f * 1e9).to_i).to be >= 1e9
      end
    end

    context 'with time_provider set to :realtime_with_timecop' do
      before(:each) do
        Datadog.configure do |c|
          c.time_provider = :realtime_with_timecop
        end
      end

      after(:each) do
        Datadog.configuration.reset!
      end

      context 'with timecop frozen time' do
        require 'timecop'

        it 'should record the correct start and end time when started outside a freeze block' do
          span.start

          Timecop.freeze(Time.now + (3600 * 24)) do
            sleep(0.0001)
            span.finish
          end

          expect((subject.to_f * 1e9).to_i).to be < 1e9
          expect((subject.to_f * 1e9).to_i).to be > 0

          # testing that the span end_time wasn't set a day in the future
          expect(span.end_time - span.start_time).to be < 1e9
          expect(span.end_time - span.start_time).to be > 0
        end

        it 'should record the correct start and end time within a freeze block' do
          Timecop.freeze(Time.now + (3600 * 24)) do
            span.start
            sleep(0.0001)
            span.finish
          end

          expect((subject.to_f * 1e9).to_i).to be > 0
          expect((subject.to_f * 1e9).to_i).to be < 1e9

          # testing that the span end_time wasn't set a day in the future
          expect(span.end_time - span.start_time).to be < 1e9
          expect(span.end_time - span.start_time).to be > 0
        end
      end
    end
  end

  describe '#clear_tag' do
    subject(:clear_tag) { span.clear_tag(key) }
    let(:key) { 'key' }

    before { span.set_tag(key, value) }
    let(:value) { 'value' }

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

    before { span.set_metric(key, value) }
    let(:value) { 1.0 }

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

    context 'given http.status_code' do
      let(:key) { 'http.status_code' }
      let(:value) { 200 }

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

    shared_examples 'setting sampling priority tag' do |key, expected_value|
      before { set_tag }

      context "given #{key}" do
        let(:key) { key }

        context 'with nil value' do
          # This could be `nil`, or any other value, as long as it isn't "false"
          let(:value) { nil }

          it 'sets the correct sampling priority' do
            expect(context.sampling_priority).to eq(expected_value)
          end

          it 'does not set a tag' do
            expect(span.get_tag(key)).to be nil
          end
        end

        context 'with true value' do
          # We only check for `== false`, but test with `true` to be sure it works
          let(:value) { true }

          it 'sets the correct sampling priority' do
            expect(context.sampling_priority).to eq(expected_value)
          end

          it 'does not set a tag' do
            expect(span.get_tag(key)).to be nil
          end
        end

        context 'with false value' do
          let(:value) { false }

          it 'does not set the sampling priority' do
            expect(context.sampling_priority).to_not eq(expected_value)
          end

          it 'does not set a tag' do
            expect(span.get_tag(key)).to be nil
          end
        end
      end
    end

    # TODO: Remove when ForcedTracing is fully deprecated
    it_behaves_like('setting sampling priority tag',
                    Datadog::Ext::ForcedTracing::TAG_KEEP,
                    Datadog::Ext::Priority::USER_KEEP)
    it_behaves_like('setting sampling priority tag',
                    Datadog::Ext::ForcedTracing::TAG_DROP,
                    Datadog::Ext::Priority::USER_REJECT)

    it_behaves_like('setting sampling priority tag',
                    Datadog::Ext::ManualTracing::TAG_KEEP,
                    Datadog::Ext::Priority::USER_KEEP)
    it_behaves_like('setting sampling priority tag',
                    Datadog::Ext::ManualTracing::TAG_DROP,
                    Datadog::Ext::Priority::USER_REJECT)
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
      expect(span).to have_error_stack(backtrace.join($RS))
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

    context 'with a finished span' do
      before { span.finish }

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
