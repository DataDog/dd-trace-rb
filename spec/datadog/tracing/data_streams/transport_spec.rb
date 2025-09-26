# frozen_string_literal: true

require 'datadog/tracing/data_streams/processor'

RSpec.describe 'Data Streams Monitoring Transport' do
  let(:processor) { Datadog::Tracing::DataStreams::Processor.new }
  let(:start_time) { 1609459200.0 }

  before do
    # Mock agent configuration
    allow(Datadog.configuration.agent).to receive(:host).and_return('localhost')
    allow(Datadog.configuration.agent).to receive(:port).and_return(8126)
    allow(Datadog.configuration).to receive(:service).and_return('ruby-service')
  end

  describe 'agent transport integration' do
    it 'sends properly formatted payload to agent' do
      # Arrange: Create some checkpoint data
      initial_context = Datadog::Tracing::DataStreams::PathwayContext.new(0, start_time, start_time)
      processor.set_pathway_context(initial_context)
      processor.set_checkpoint(['service:api', 'direction:in'], start_time + 1)

      # Mock the HTTP request
      mock_response = double('response', code: '200', message: 'OK')
      allow(processor).to receive(:send_dsm_payload).and_return(mock_response)

      # Act: Flush stats
      processor.flush_stats

      # Assert: Verify the payload was sent with correct format
      expect(processor).to have_received(:send_dsm_payload) do |data, headers|
        expect(headers['Content-Type']).to eq('application/msgpack')
        expect(headers['Content-Encoding']).to eq('gzip')
        expect(headers['Datadog-Meta-Lang']).to eq('ruby')
        expect(headers['Datadog-Meta-Tracer-Version']).to eq(Datadog::VERSION::STRING)

        # Verify data is compressed msgpack
        expect(data).to be_a(String)
        expect(data.bytesize).to be > 0
      end
    end

    it 'handles transport errors gracefully' do
      # Arrange: Create checkpoint data
      initial_context = Datadog::Tracing::DataStreams::PathwayContext.new(0, start_time, start_time)
      processor.set_pathway_context(initial_context)
      processor.set_checkpoint(['service:api'], start_time + 1)

      # Mock transport error
      allow(processor).to receive(:send_dsm_payload).and_raise(StandardError.new('Network error'))

      # Act & Assert: Should not raise error
      expect { processor.flush_stats }.not_to raise_error
    end

    it 'sends to correct agent endpoint' do
      # Arrange: Create checkpoint data
      initial_context = Datadog::Tracing::DataStreams::PathwayContext.new(0, start_time, start_time)
      processor.set_pathway_context(initial_context)
      processor.set_checkpoint(['service:api'], start_time + 1)

      # Mock HTTP client to verify endpoint
      mock_http = double('http')
      mock_request = double('request')
      mock_response = double('response', code: '200', message: 'OK')

      allow(Net::HTTP).to receive(:new).with('localhost', 8126).and_return(mock_http)
      allow(mock_http).to receive(:use_ssl=).with(false)
      allow(Net::HTTP::Post).to receive(:new).and_return(mock_request)
      allow(mock_request).to receive(:[]=)
      allow(mock_request).to receive(:body=)
      allow(mock_http).to receive(:request).with(mock_request).and_return(mock_response)

      # Act: Flush stats
      processor.flush_stats

      # Assert: Verify correct endpoint was used
      expect(Net::HTTP::Post).to have_received(:new).with(URI('http://localhost:8126/v0.1/pipeline_stats'))
    end
  end

  describe 'payload format validation' do
    it 'creates properly structured msgpack payload' do
      # Arrange: Create checkpoint data
      initial_context = Datadog::Tracing::DataStreams::PathwayContext.new(0, start_time, start_time)
      processor.set_pathway_context(initial_context)
      processor.set_checkpoint(['service:api', 'direction:in'], start_time + 1)

      # Capture the payload before compression
      captured_payload = nil
      allow(processor).to receive(:send_stats_to_agent) do |payload|
        captured_payload = payload
      end

      # Act: Flush stats
      processor.flush_stats

      # Assert: Verify payload structure
      expect(captured_payload).to include(
        'Service' => 'ruby-service',
        'TracerVersion' => Datadog::VERSION::STRING,
        'Lang' => 'ruby',
        'Stats' => be_an(Array),
        'Hostname' => be_a(String)
      )

      expect(captured_payload['Stats']).to have(1).item
      bucket = captured_payload['Stats'].first
      expect(bucket).to include('Start', 'Duration', 'Stats', 'Backlogs')
    end
  end
end
