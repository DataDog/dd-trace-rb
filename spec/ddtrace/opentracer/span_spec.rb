require 'spec_helper'

require 'ddtrace/opentracer'
require 'ddtrace/opentracer/helper'

if Datadog::OpenTracer.supported?
  RSpec.describe Datadog::OpenTracer::Span do
    include_context 'OpenTracing helpers'

    subject(:span) { described_class.new }

    describe '#operation_name=' do
      subject(:result) { span.operation_name = name }
      let(:name) { 'execute_job' }

      it { expect(result).to eq(name) }
    end

    describe '#context' do
      subject(:context) { span.context }
      it { is_expected.to be(OpenTracing::SpanContext::NOOP_INSTANCE) }
    end

    describe '#set_tag' do
      subject(:result) { span.set_tag(key, value) }
      let(:key) { 'account_id' }
      let(:value) { '1234' }
      it { is_expected.to be(span) }
    end

    describe '#set_baggage_item' do
      subject(:result) { span.set_baggage_item(key, value) }
      let(:key) { 'account_id' }
      let(:value) { '1234' }
      it { is_expected.to be(span) }
    end

    describe '#get_baggage_item' do
      subject(:result) { span.get_baggage_item(key) }
      let(:key) { 'account_id' }
      it { is_expected.to be nil }
    end

    describe '#log' do
      subject(:log) { span.log(event: event, timestamp: timestamp, **fields) }
      let(:event) { 'job_finished' }
      let(:timestamp) { Time.now }
      let(:fields) { { time_started: Time.now, account_id: '1234' } }

      before(:each) do
        expect { log }.to output("Span#log is deprecated.  Please use Span#log_kv instead.\n").to_stderr
      end

      it { is_expected.to be nil }
    end

    describe '#log_kv' do
      subject(:log_kv) { span.log_kv(timestamp: timestamp, **fields) }
      let(:timestamp) { Time.now }
      let(:fields) { { time_started: Time.now, account_id: '1234' } }

      before(:each) do
        expect { log_kv }.to_not output.to_stderr
      end

      it { is_expected.to be nil }
    end
  end
end
