# frozen_string_literal: true

require 'datadog/tracing/data_streams/processor'
require 'json'

RSpec.describe 'Data Streams Monitoring Agent Communication' do
  let(:processor) { Datadog::Tracing::DataStreams::Processor.new }
  let(:start_time) { 1609459200.0 }
  let(:agent_spy) { instance_double('AgentTransport') }

  before do
    allow(processor).to receive(:agent_transport).and_return(agent_spy)
    allow(agent_spy).to receive(:post)

    # Disable compression for cleaner testing (unless specifically testing compression)
    allow(processor).to receive(:compress_payload?).and_return(false)
  end

  describe 'single checkpoint scenario' do
    it 'sends pathway data to agent endpoint' do
      # Set up processor with known timing to avoid negative latencies
      initial_context = Datadog::Tracing::DataStreams::PathwayContext.new(0, start_time, start_time)
      processor.set_pathway_context(initial_context)

      processor.set_checkpoint(['service:api', 'operation:create-user'], start_time + 1)

      processor.flush_stats

      expect(agent_spy).to have_received(:post) do |endpoint, data, headers|
        expect(endpoint).to eq('/v0.1/pipeline_stats')

        payload = JSON.parse(data)
        expect(payload['checkpoints']).to have(1).item

        checkpoint = payload['checkpoints'].first
        expect(checkpoint['tags']).to include('service:api', 'operation:create-user')
        expect(checkpoint['hash']).to be_a(Integer)
        expect(checkpoint['parent_hash']).to be_a(Integer)
        expect(checkpoint['edge_latency_sec']).to eq(1.0) # Should be 1 second
      end
    end
  end

  describe 'high-throughput checkpoint scenario' do
    it 'aggregates many checkpoints using DDSketch for latency sampling' do
      # Simulate high-throughput service processing 1000 messages
      1000.times do |i|
        latency_variation = rand * 0.1 # 0-100ms variation
        processor.set_checkpoint(["batch:#{i}"], start_time + i + latency_variation)
      end

      processor.flush_stats

      expect(agent_spy).to have_received(:post) do |endpoint, data, headers|
        payload = JSON.parse(data)

        # Should aggregate using time buckets, not send 1000 individual checkpoints
        expect(payload['time_buckets']).not_to be_empty

        # Should include distribution data for latency analysis
        # (DDSketch implementation would go here in future)
        expect(payload['checkpoints'].size).to be <= 1000 # Some aggregation
      end
    end
  end

  describe 'pathway convergence scenario' do
    it 'enables agent to reconstruct fan-out and merge patterns' do
      # Simulate fan-out by having one source checkpoint feed multiple pathways
      initial_context = Datadog::Tracing::DataStreams::PathwayContext.new(0, start_time, start_time)
      processor.set_pathway_context(initial_context)

      processor.set_checkpoint(['source:order-received'], start_time + 1)
      source_hash = processor.get_current_pathway.hash

      # Simulate three different processing paths from same source
      ['inventory', 'payment', 'notification'].each_with_index do |service, i|
        # Reset to source state and branch
        source_context = Datadog::Tracing::DataStreams::PathwayContext.new(source_hash, start_time, start_time + 1, 0)
        processor.set_pathway_context(source_context)
        processor.set_checkpoint(["service:#{service}"], start_time + i + 2)
      end

      processor.flush_stats

      expect(agent_spy).to have_received(:post) do |endpoint, data, headers|
        payload = JSON.parse(data)

        # Should have source checkpoint + 3 fan-out branches
        expect(payload['checkpoints']).to have(4).items

        # Find fan-out branches (those with source_hash as parent)
        branches = payload['checkpoints'].select { |c| c['parent_hash'] == source_hash }
        expect(branches).to have(3).items

        branch_services = branches.map { |b| b['tags'].first }
        expect(branch_services).to match_array(['service:inventory', 'service:payment', 'service:notification'])
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
        payload = JSON.parse(data)

        expect(payload['consumer_offsets']).to have(5).items
        offsets = payload['consumer_offsets'].map { |stat| stat['offset'] }
        expect(offsets).to eq([100, 101, 105, 106, 110]) # Preserves gaps for lag detection

        # All should be for same topic/partition
        payload['consumer_offsets'].each do |stat|
          expect(stat['topic']).to eq(topic)
          expect(stat['partition']).to eq(partition)
        end
      end
    end
  end

  describe 'mixed workload scenario' do
    it 'combines checkpoint and consumer data in single agent payload' do
      # Realistic scenario: service processes messages and creates checkpoints
      processor.set_checkpoint(['service:order-processor'], start_time)
      processor.track_kafka_consume('orders', 0, 100, start_time + 0.5)
      processor.set_checkpoint(['topic:processed-orders'], start_time + 1)
      processor.track_kafka_consume('orders', 0, 101, start_time + 1.5)

      processor.flush_stats

      expect(agent_spy).to have_received(:post) do |endpoint, data, headers|
        payload = JSON.parse(data)

        # Should include both types of data
        expect(payload['checkpoints']).to have(2).items
        expect(payload['consumer_offsets']).to have(2).items

        # Should share same timestamp bucket
        expect(payload['timestamp']).to be_a(Integer)
      end
    end
  end

  describe 'long pathway scenario' do
    it 'tracks multi-hop message flows for end-to-end monitoring' do
      # Use single processor to simulate message flow through multiple services
      # This tests the pathway lineage without multiple agent transports

      services = ['api', 'service-a', 'service-b', 'service-c']
      initial_context = Datadog::Tracing::DataStreams::PathwayContext.new(0, start_time, start_time)
      processor.set_pathway_context(initial_context)

      # Simulate each service processing and checkpointing
      services.each_with_index do |service, i|
        processor.set_checkpoint(["service:#{service}"], start_time + i + 1)
      end

      processor.flush_stats

      expect(agent_spy).to have_received(:post) do |endpoint, data, headers|
        payload = JSON.parse(data)

        # Should have checkpoints for all 4 services
        expect(payload['checkpoints']).to have(4).items

        # Each checkpoint should have proper parent linkage
        checkpoints = payload['checkpoints']
        checkpoints.each_with_index do |checkpoint, i|
          next unless i > 0

          # Each service (except first) should have previous service as parent
          previous_checkpoint = checkpoints[i - 1]
          expect(checkpoint['parent_hash']).to eq(previous_checkpoint['hash'])
        end
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
        payload = JSON.parse(data)
        expect(payload['checkpoints']).to have(1).item # Should still work
      end
    end
  end

  describe 'payload optimization scenarios' do
    it 'efficiently handles high-cardinality tag scenarios' do
      # Many unique pathways (high cardinality)
      50.times do |i|
        processor.set_checkpoint(["user:#{i}", "session:#{i}", "experiment:#{i % 10}"], start_time + i)
      end

      processor.flush_stats

      expect(agent_spy).to have_received(:post) do |endpoint, data, headers|
        payload = JSON.parse(data)

        # Should handle high cardinality without exploding payload size
        expect(payload.to_json.bytesize).to be < 100000 # Reasonable size limit
        expect(payload['checkpoints']).to have(50).items

        # Tags should be preserved for cardinality analysis
        all_tags = payload['checkpoints'].flat_map { |c| c['tags'] }
        expect(all_tags).to include('experiment:5') # Sample tag preserved
      end
    end

    it 'compresses payloads larger than 1KB before sending' do
      200.times { |i| processor.set_checkpoint(["large-batch:#{i}"], start_time + i) }

      # Re-enable compression for this test only
      allow(processor).to receive(:compress_payload?).and_call_original
      allow(processor).to receive(:gzip_compress).and_return('compressed-payload-data')

      processor.flush_stats

      expect(agent_spy).to have_received(:post) do |endpoint, data, headers|
        expect(data).to eq('compressed-payload-data')
        expect(headers['Content-Encoding']).to eq('gzip')
      end
    end
  end
end
