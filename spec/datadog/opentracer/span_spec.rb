require 'spec_helper'

require 'time'

require 'datadog/tracing/metadata/ext'
require 'datadog/tracing/span_operation'
require 'datadog/opentracer'

RSpec.describe Datadog::OpenTracer::Span do
  subject(:span) { described_class.new(datadog_span: datadog_span, span_context: span_context) }

  let(:datadog_span) { instance_double(Datadog::Tracing::SpanOperation) }
  let(:span_context) { instance_double(Datadog::OpenTracer::SpanContext) }

  describe '#operation_name=' do
    subject(:result) { span.operation_name = name }

    let(:name) { 'execute_job' }

    before { expect(datadog_span).to receive(:name=).with(name).and_return(name) }

    it { expect(result).to eq(name) }
  end

  describe '#context' do
    subject(:context) { span.context }

    it { is_expected.to be(span_context) }
  end

  describe '#set_tag' do
    subject(:result) { span.set_tag(key, value) }

    context 'when given arbitrary tag key and value' do
      let(:key) { 'account_id' }
      let(:value) { '1234' }

      before { expect(datadog_span).to receive(:set_tag).with(key, value) }

      it { is_expected.to be(span) }
    end

    context 'when given an error tag of true' do
      let(:key) { 'error' }
      let(:value) { true }

      before { expect(datadog_span).to receive(:set_tag).with(key, value) }

      before { expect(datadog_span).to receive(:'status=').with(Datadog::Tracing::Metadata::Ext::Errors::STATUS) }

      it { is_expected.to be(span) }
    end

    context 'when given an error tag of false' do
      let(:key) { 'error' }
      let(:value) { false }

      before { expect(datadog_span).to receive(:set_tag).with(key, value) }

      before { expect(datadog_span).to receive(:'status=').with(0) }

      it { is_expected.to be(span) }
    end
  end

  describe '#set_baggage_item' do
    subject(:result) { span.set_baggage_item(key, value) }

    let(:key) { 'account_id' }
    let(:value) { '1234' }
    let(:new_span_context) { instance_double(Datadog::OpenTracer::SpanContext) }

    it 'creates a new SpanContext with the baggage item' do
      expect(Datadog::OpenTracer::SpanContextFactory).to receive(:clone)
        .with(span_context: span_context, baggage: hash_including(key => value))
        .and_return(new_span_context)

      is_expected.to be(span)
      expect(span.context).to be(new_span_context)
    end
  end

  describe '#get_baggage_item' do
    subject(:result) { span.get_baggage_item(key) }

    let(:key) { 'account_id' }
    let(:value) { '1234' }
    let(:baggage) { { key => value } }

    before { allow(span_context).to receive(:baggage).and_return(baggage) }

    it { is_expected.to be(value) }
  end

  describe '#log' do
    subject(:log) { span.log(event: event, timestamp: timestamp, **fields) }

    let(:event) { 'job_finished' }
    let(:timestamp) { Time.now }
    let(:fields) { { time_started: Time.now, account_id: '1234' } }

    # Expect a deprecation warning to be output.
    it do
      expect { log }.to output("Span#log is deprecated.  Please use Span#log_kv instead.\n").to_stderr
    end
  end

  describe '#log_kv' do
    subject(:log_kv) { span.log_kv(timestamp: timestamp, **fields) }

    let(:timestamp) { Time.now }

    context 'when given arbitrary key/value pairs' do
      let(:fields) { { time_started: Time.now, account_id: '1234' } }
      # We don't expect this to do anything right now.

      it { is_expected.to be nil }
    end

    context 'when given an \'error.object\'' do
      let(:fields) { { :'error.object' => error_object } }
      let(:error_object) { instance_double(StandardError) }

      before { expect(datadog_span).to receive(:set_error).with(error_object) }

      it { is_expected.to be nil }
    end
  end
end
