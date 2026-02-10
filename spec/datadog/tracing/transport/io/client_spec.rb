require 'spec_helper'

require 'stringio'
require 'json'
require 'datadog/tracing/transport/io/client'
require 'datadog/tracing/transport/io/traces'

RSpec.describe Datadog::Tracing::Transport::IO::Client do
  subject(:client) { described_class.new(out, encoder) }

  let(:out) { instance_double(IO) }
  let(:encoder) { instance_double(Datadog::Core::Encoding::Encoder) }

  describe '#initialize' do
    it { is_expected.to be_a_kind_of Datadog::Tracing::Transport::Statistics }

    it 'has the correct default properties' do
      is_expected.to have_attributes(
        out: out,
        encoder: encoder
      )
    end
  end

  describe '#send_request' do
    context 'given a request' do
      subject(:send_request) { client.send_request(request) }

      let(:request) { instance_double(Datadog::Core::Transport::Request, parcel: parcel) }
      let(:parcel) { instance_double(Datadog::Core::Transport::Parcel, data: data) }
      let(:data) { 'Hello, world!' }
      let(:result) { double('IO result') }

      before do
        expect(client.out).to receive(:puts)
          .with(data)
          .and_return(result)

        expect(client).to receive(:update_stats_from_response!)
          .with(kind_of(Datadog::Tracing::Transport::IO::Response))

        send_request
      end

      it do
        is_expected.to be_a_kind_of(Datadog::Tracing::Transport::IO::Response)
        expect(send_request.result).to eq(result)
      end
    end

    context 'given a request and block' do
      subject(:send_request) do
        client.send_request(request) do |out, request|
          expect(out).to be(client.out)
          expect(request).to be(request)
          response
        end
      end

      let(:request) { instance_double(Datadog::Core::Transport::Request) }
      let(:response) { instance_double(Datadog::Tracing::Transport::IO::Response) }

      before do
        expect(client).to receive(:update_stats_from_response!)
          .with(response)

        send_request
      end

      it do
        is_expected.to be response
      end
    end
  end

  describe '#write_data' do
    subject(:write_data) { client.write_data(out, data) }

    let(:data) { double('data') }
    let(:result) { double('result') }

    before do
      expect(out)
        .to receive(:puts)
        .with(data)
        .and_return(result)
    end

    it { is_expected.to be result }
  end

  describe '#build_response' do
    subject(:build_response) { client.build_response(request, data, result) }

    let(:request) { instance_double(Datadog::Core::Transport::Request) }
    let(:data) { double('data') }
    let(:result) { double('result') }
    let(:response) { instance_double(Datadog::Tracing::Transport::IO::Response) }

    before do
      expect(Datadog::Tracing::Transport::IO::Response)
        .to receive(:new)
        .with(result)
        .and_return(response)
    end

    it { is_expected.to be response }
  end

  describe '#send_traces' do
    context 'integration test with real IO' do
      subject(:send_traces) { client.send_traces(traces) }

      let(:out) { StringIO.new }
      let(:encoder) { Datadog::Core::Encoding::JSONEncoder }
      let(:traces) { get_test_traces(2) }

      it 'writes valid JSON with correct trace structure' do
        # Send traces and capture output
        responses = send_traces
        output = out.string

        # Verify response
        expect(responses).to all(be_a(Datadog::Tracing::Transport::IO::Traces::Response))

        # Parse and verify it's valid JSON
        parsed = JSON.parse(output)
        expect(parsed).to be_a(Hash)
        expect(parsed).to have_key('traces')
        expect(parsed['traces']).to be_an(Array)
        expect(parsed['traces'].length).to eq(traces.length)

        # Verify all traces have correct structure
        traces.zip(parsed['traces']).each do |trace, encoded_trace|
          expect(encoded_trace).to be_an(Array)
          expect(encoded_trace.length).to eq(trace.spans.length)

          # Verify all spans in the trace are correctly encoded
          trace.spans.zip(encoded_trace).each do |span, encoded_span|
            # Match complete encoded span structure
            expect(encoded_span).to match(
              'error' => 0,
              'meta' => {},
              'metrics' => be_a(Hash),
              'meta_struct' => {},
              'name' => 'client.testing',
              'parent_id' => match(/^[0-9a-f]+$/),
              'resource' => '/traces',
              'service' => 'test-app',
              'span_id' => match(/^[0-9a-f]+$/),
              'trace_id' => match(/^[0-9a-f]+$/),
              'type' => 'web',
              'span_links' => [],
              'start' => be_an(Integer),
              'duration' => be_an(Integer),
            )

            # Verify hex-encoded IDs match actual span values
            expect(encoded_span['trace_id']).to eq(span.trace_id.to_s(16))
            expect(encoded_span['span_id']).to eq(span.id.to_s(16))
            expect(encoded_span['parent_id']).to eq(span.parent_id.to_s(16))
          end
        end
      end
    end
  end
end
