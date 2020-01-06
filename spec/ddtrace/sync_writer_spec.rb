require 'spec_helper'

require 'ddtrace'
require 'ddtrace/sync_writer'

RSpec.describe Datadog::SyncWriter do
  subject(:sync_writer) { described_class.new }

  describe '#runtime_metrics' do
    subject(:runtime_metrics) { sync_writer.runtime_metrics }
    it { is_expected.to be_a_kind_of(Datadog::Runtime::Metrics) }
  end

  describe '#write' do
    subject(:write) { sync_writer.write(trace, services) }
    let(:trace) { get_test_traces(1).first }
    let(:services) { nil }

    context 'with report hostname' do
      let(:hostname) { 'my-host' }

      before(:each) do
        allow(Datadog::Runtime::Socket).to receive(:hostname).and_return(hostname)
      end

      context 'enabled' do
        around do |example|
          Datadog.configuration.report_hostname = Datadog.configuration.report_hostname.tap do
            Datadog.configuration.report_hostname = true
            example.run
          end
        end

        it do
          expect(sync_writer.transport).to receive(:send) do |_type, traces|
            root_span = traces.first.first
            expect(root_span.get_tag(Datadog::Ext::NET::TAG_HOSTNAME)).to eq(hostname)

            # Stub successful request
            200
          end

          write
        end
      end

      context 'disabled' do
        around do |example|
          Datadog.configuration.report_hostname = Datadog.configuration.report_hostname.tap do
            Datadog.configuration.report_hostname = false
            example.run
          end
        end

        it do
          expect(sync_writer.transport).to receive(:send) do |_type, traces|
            root_span = traces.first.first
            expect(root_span.get_tag(Datadog::Ext::NET::TAG_HOSTNAME)).to be nil

            # Stub successful request
            200
          end

          write
        end
      end
    end
  end

  describe 'integration' do
    context 'when initializing a tracer' do
      subject(:tracer) { Datadog::Tracer.new(writer: sync_writer) }
      it { expect(tracer.writer).to be sync_writer }
    end

    context 'when configuring a tracer' do
      subject(:tracer) { Datadog::Tracer.new }
      before { tracer.configure(writer: sync_writer) }
      it { expect(tracer.writer).to be sync_writer }
    end
  end
end
