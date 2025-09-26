# frozen_string_literal: true

require 'datadog/tracing/data_streams/processor'
require 'json'
require 'msgpack'

# Fake DDSketch for testing
class FakeDDSketch
  def self.supported?
    true
  end

  def initialize
    @values = []
  end

  def add(value)
    @values << value
    self
  end

  def count
    @values.size.to_f
  end

  def encode
    # Return fake protobuf data and reset like real DDSketch
    result = "fake-ddsketch-protobuf-#{@values.size}-values"
    @values.clear
    result
  end
end

RSpec.describe 'Data Streams Monitoring Agent Communication' do
  let(:processor) { Datadog::Tracing::DataStreams::Processor.new(ddsketch_class: FakeDDSketch) }
  let(:start_time) { 1609459200.0 }
  let(:agent_spy) { instance_double('AgentTransport') }

  before do
    allow(processor).to receive(:agent_transport).and_return(agent_spy)
    allow(agent_spy).to receive(:post)

    # Disable gzip compression for easier testing
    allow(processor).to receive(:gzip_compress) { |data| data }

    # Configure service name for tests
    Datadog.configure { |c| c.service = 'ruby-service' }
  end

  describe 'single checkpoint scenario' do
    it 'sends pathway data to agent endpoint' do
      initial_context = Datadog::Tracing::DataStreams::PathwayContext.new(0, start_time, start_time)
      processor.set_pathway_context(initial_context)

      processor.set_checkpoint(['service:api', 'operation:create-user'], start_time + 1)

      processor.flush_stats

      expect(agent_spy).to have_received(:post) do |endpoint, data, headers|
        expect(endpoint).to eq('/v0.1/pipeline_stats')
        expect(headers['Content-Type']).to eq('application/msgpack')

        payload = MessagePack.unpack(data)
        expect(payload['Service']).to eq('ruby-service')
        expect(payload['Lang']).to eq('ruby')
        expect(payload['Stats']).to have(1).item

        bucket = payload['Stats'].first
        expect(bucket['Stats']).to have(1).item

        stat = bucket['Stats'].first
        expect(stat['EdgeLatency']).to be_a(String) # DDSketch protobuf
        expect(stat['EdgeLatency'].bytesize).to be > 0
        expect(stat['PathwayLatency']).to be_a(String) # DDSketch protobuf
      end
    end
  end

  describe 'high-throughput checkpoint scenario' do
    it 'handles many pathway steps using DDSketch for each step' do
      initial_context = Datadog::Tracing::DataStreams::PathwayContext.new(0, start_time, start_time)
      processor.set_pathway_context(initial_context)

      # Simulate high-throughput service processing 1000 messages (same tags = aggregates)
      1000.times do |i|
        latency_variation = rand * 0.1 # 0-100ms variation
        processor.set_checkpoint(
          ['service:batch-processor', 'operation:process'],
          start_time + i * 0.001 + latency_variation
        )
      end

      processor.flush_stats

      expect(agent_spy).to have_received(:post) do |endpoint, data, headers|
        expect(headers['Content-Type']).to eq('application/msgpack')

        payload = MessagePack.unpack(data)
        bucket = payload['Stats'].first

        # Each set_checkpoint creates a different pathway hash (1000 separate pathways)
        expect(bucket['Stats']).to have(1000).items # Each checkpoint advances pathway

        # Verify DDSketch is used for each pathway
        bucket['Stats'].each do |stat|
          expect(stat['EdgeLatency']).to be_a(String) # DDSketch protobuf format
          expect(stat['PathwayLatency']).to be_a(String) # DDSketch protobuf format
        end
      end
    end
  end

  describe 'consumer and producer scenario' do
    it 'tracks different latencies for direction:in and direction:out operations' do
      initial_context = Datadog::Tracing::DataStreams::PathwayContext.new(0, start_time, start_time)
      processor.set_pathway_context(initial_context)

      # Consumer operation
      processor.set_checkpoint(['service:order-processor', 'direction:in'], start_time + 0.050)

      # Producer operation (same service, different direction)
      processor.set_checkpoint(['service:order-processor', 'direction:out'], start_time + 0.100)

      processor.flush_stats

      expect(agent_spy).to have_received(:post) do |endpoint, data, headers|
        payload = MessagePack.unpack(data)
        bucket = payload['Stats'].first

        # Different tags + pathway advancement = 2 separate pathway stats
        expect(bucket['Stats']).to have(2).items # direction:in and direction:out are separate

        # Verify DDSketch is used for each pathway
        bucket['Stats'].each do |stat|
          expect(stat['EdgeLatency']).to be_a(String) # DDSketch protobuf format
          expect(stat['PathwayLatency']).to be_a(String) # DDSketch protobuf format
        end
      end
    end
  end

  describe 'consumer offset tracking scenario' do
    it 'sends consumer progress data for throughput and lag monitoring' do
      topic = 'user-events'
      partition = 0

      # Simulate consumer processing message stream with some lag
      [100, 101, 105, 106, 110].each_with_index do |offset, i| # Gaps indicate lag
        processor.track_kafka_consume(topic, partition, offset, start_time + i)
      end

      processor.flush_stats

      expect(agent_spy).to have_received(:post) do |endpoint, data, headers|
        payload = MessagePack.unpack(data)
        bucket = payload['Stats'].first
        backlogs = bucket['Backlogs']

        expect(backlogs).to have(5).items
        offsets = backlogs.map { |backlog| backlog['Value'] }
        expect(offsets).to eq([100, 101, 105, 106, 110]) # Preserves gaps for lag detection

        # All should be kafka_consume type
        backlogs.each do |backlog|
          expect(backlog['Tags']).to include('type:kafka_consume')
          expect(backlog['Tags']).to include("topic:#{topic}")
          expect(backlog['Tags']).to include("partition:#{partition}")
        end
      end
    end
  end

  describe 'mixed workload scenario' do
    it 'combines checkpoint and consumer data in single agent payload' do
      initial_context = Datadog::Tracing::DataStreams::PathwayContext.new(0, start_time, start_time)
      processor.set_pathway_context(initial_context)

      # Realistic scenario: service processes messages and creates checkpoints
      processor.set_checkpoint(['service:order-processor'], start_time + 0.5)
      processor.track_kafka_consume('orders', 0, 100, start_time + 0.5)
      processor.set_checkpoint(['topic:processed-orders'], start_time + 1)
      processor.track_kafka_consume('orders', 0, 101, start_time + 1.5)

      processor.flush_stats

      expect(agent_spy).to have_received(:post) do |endpoint, data, headers|
        payload = MessagePack.unpack(data)
        bucket = payload['Stats'].first

        # Should include both types of data
        expect(bucket['Stats']).to have(2).items # Two different pathway steps (advancement)
        expect(bucket['Backlogs']).to have(2).items # Individual consumer offsets

        # Verify structure
        stat = bucket['Stats'].first
        expect(stat['EdgeLatency']).to be_a(String) # DDSketch data
        expect(bucket['Backlogs'].first['Tags']).to include('type:kafka_consume')
      end
    end
  end

  describe 'error resilience scenarios' do
    it 'continues operating when agent is unavailable' do
      processor.set_checkpoint(['service:resilient'])

      allow(processor).to receive(:send_stats_to_agent).and_raise(StandardError, 'Connection refused')

      expect { processor.flush_stats }.not_to raise_error
      expect { processor.set_checkpoint(['service:still-works']) }.not_to raise_error
    end

    it 'handles malformed pathway context gracefully' do
      processor.decode_and_set_pathway_context({ 'dd-pathway-ctx-base64' => 'invalid-base64!' })
      processor.set_checkpoint(['service:recovery'])

      processor.flush_stats

      expect(agent_spy).to have_received(:post) do |endpoint, data, headers|
        payload = MessagePack.unpack(data)
        bucket = payload['Stats'].first

        expect(bucket['Stats']).to have(1).item # Should still work
        stat = bucket['Stats'].first
        expect(stat['EdgeLatency']).to be_a(String)
      end
    end
  end
end
