require 'spec_helper'

require 'json'
require 'msgpack'
require 'pp'
require 'time'

require 'datadog/core'
require 'datadog/core/utils'
require 'datadog/core/utils/time'
require 'datadog/tracing/metadata/ext'
require 'datadog/tracing/span'

RSpec.describe Datadog::Tracing::Span do
  subject(:span) { described_class.new(name, **span_options) }

  let(:name) { 'my.span' }
  let(:span_options) { {} }

  before do
    Datadog.configure {}
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

    context 'service_entry' do
      context 'with nil' do
        let(:span_options) { { service_entry: nil } }

        it 'does not tag as top-level' do
          expect(span).to_not have_metadata('_dd.top_level')
        end
      end

      context 'with false' do
        let(:span_options) { { service_entry: false } }

        it 'does not tag as top-level' do
          expect(span).to_not have_metadata('_dd.top_level')
        end
      end

      context 'with true' do
        let(:span_options) { { service_entry: true } }

        it 'tags as top-level' do
          expect(span).to have_metadata('_dd.top_level' => 1.0)
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

  describe '#started?' do
    subject(:started?) { span.started? }

    context 'when span hasn\'t been started or stopped' do
      it { is_expected.to be false }
    end

    it { expect { span.start_time = Time.now }.to change { span.started? }.from(false).to(true) }
    it { expect { span.end_time = Time.now }.to_not change { span.started? }.from(false) }
  end

  describe '#stopped?' do
    subject(:stopped?) { span.stopped? }

    context 'when span hasn\'t been started or stopped' do
      it { is_expected.to be false }
    end

    it { expect { span.start_time = Time.now }.to_not change { span.stopped? }.from(false) }
    it { expect { span.end_time = Time.now }.to change { span.stopped? }.from(false).to(true) }
  end

  describe '#duration' do
    subject(:duration) { span.duration }

    it { is_expected.to be nil }

    context 'when :duration is set' do
      let(:duration_value) { instance_double(Float) }
      before { span.duration = duration_value }
      it { is_expected.to be duration_value }
    end

    context 'when only :start_time is set' do
      let(:start_time) { Time.now }
      before { span.start_time = start_time }
      it { is_expected.to be nil }
    end

    context 'when only :end_time is set' do
      let(:end_time) { Time.now }
      before { span.end_time = end_time }
      it { is_expected.to be nil }
    end

    context 'when :start_time and :end_time are set' do
      let(:start_time) { Time.now }
      let(:end_time) { Time.now }

      before do
        span.start_time = start_time
        span.end_time = end_time
      end

      it { is_expected.to eq(end_time - start_time) }
    end
  end

  describe '#set_error' do
    subject(:set_error) { span.set_error(error) }

    context 'given nil' do
      let(:error) { nil }

      before { set_error }

      it do
        expect(span.status).to eq(Datadog::Tracing::Metadata::Ext::Errors::STATUS)
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::Errors::TAG_TYPE)).to be nil
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::Errors::TAG_MSG)).to be nil
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::Errors::TAG_STACK)).to be nil
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
        expect(span.status).to eq(Datadog::Tracing::Metadata::Ext::Errors::STATUS)
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::Errors::TAG_TYPE)).to eq(error.class.to_s)
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::Errors::TAG_MSG)).to eq(message)
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::Errors::TAG_STACK)).to be_a_kind_of(String)
      end
    end
  end

  describe '#==' do
    subject(:equals?) { span_one == span_two }
    let(:span_one) { described_class.new('span') }
    let(:span_two) { described_class.new('span') }

    # Because #id auto-generates, this is false.
    it { is_expected.to be false }

    context 'when the #id doesn\'t match' do
      let(:span_one) { described_class.new('span', id: 1) }
      let(:span_two) { described_class.new('span', id: 2) }

      it { is_expected.to be false }
    end

    context 'when the #id matches' do
      let(:span_one) { described_class.new('span', id: 1) }
      let(:span_two) { described_class.new('span', id: 1) }

      it { is_expected.to be true }

      context 'but other properties do not' do
        let(:span_one) { described_class.new('one', id: 1) }
        let(:span_two) { described_class.new('two', id: 1) }

        # Because only #id matters, this is true.
        it { is_expected.to be true }
      end
    end
  end

  describe '#to_hash' do
    subject(:to_hash) { span.to_hash }

    let(:span_options) { { trace_id: 12 } }

    before { span.id = 34 }

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
        error: 0
      )
    end

    context 'with a stopped span' do
      before do
        span.start_time = Datadog::Core::Utils::Time.now.utc
        span.end_time = Datadog::Core::Utils::Time.now.utc
      end

      it 'includes timing information' do
        is_expected.to include(
          start: be >= 0,
          duration: be >= 0
        )
      end
    end
  end

  describe '#pretty_print' do
    subject(:pretty_print) { PP.pp(span) }

    it 'output without errors' do
      expect { pretty_print }.to output.to_stdout
    end
  end
end
