# frozen_string_literal: true

require 'datadog/core'
require 'datadog/data_streams/processor'
require 'datadog/core/ddsketch'
require_relative 'spec_helper'

# Expected deterministic hash values for specific pathways (with manual_checkpoint: false)
KAFKA_ORDERS_PRODUCE_HASH = 17981503584283442515
KAFKA_ORDERS_CONSUME_HASH = 2205397010147396424 # with carrier from produce
KAFKA_ORDERS_CONSUME_HASH_WITHOUT_CARRIER = 9826962151962828715 # without carrier
KINESIS_ORDERS_PRODUCE_HASH = 14687993552271180499
KAFKA_PAYMENTS_PRODUCE_HASH = 10550901661805295262

RSpec.describe Datadog::DataStreams::Processor do
  before do
    skip_if_data_streams_not_supported(self)
  end

  let(:logger) { instance_double(Datadog::Core::Logger, debug: nil) }
  let(:settings) { double('Settings', service: Datadog.configuration.service, env: Datadog.configuration.env) }
  let(:agent_settings) { Datadog::Core::Configuration::AgentSettings.new(adapter: :test, hostname: 'localhost', port: 9999) }
  let(:processor) { described_class.new(interval: 10.0, logger: logger, settings: settings, agent_settings: agent_settings) }

  after do
    processor.stop(true)
    processor.join
  end

  before do
    # Stub HTTP requests to the agent
    stub_request(:post, %r{http://localhost:9999/v0.1/pipeline_stats})
      .to_return(status: 200, body: '', headers: {})
  end

  describe '#initialize' do
    context 'when custom interval is provided' do
      let(:processor) do
        described_class.new(interval: 5.0, logger: logger, settings: settings, agent_settings: agent_settings)
      end

      it 'sets up periodic worker with custom interval' do
        expect(processor.loop_base_interval).to eq(5.0)
      end
    end
  end

  describe 'public checkpoint API' do
    after { processor.stop(true) }

    describe '#set_produce_checkpoint' do
      it 'returns a hash' do
        result = processor.set_produce_checkpoint(type: 'kafka', destination: 'orders')
        expect(result).to be_a(String)
        expect(result).not_to be_empty
      end

      it 'computes deterministic hash' do
        processor.set_produce_checkpoint(type: 'kafka', destination: 'orders', manual_checkpoint: false)
        expect(processor.pathway_context.hash).to eq(KAFKA_ORDERS_PRODUCE_HASH)
      end

      it 'adds the hash to the carrier' do
        carrier = {}
        returned_value = processor.set_produce_checkpoint(type: 'kafka', destination: 'orders', manual_checkpoint: false) do |key, value|
          carrier[key] = value
        end

        expect(carrier[Datadog::DataStreams::Processor::PROPAGATION_KEY]).to eq(returned_value)

        # Decode and verify the pathway context contains the expected hash
        decoded = Datadog::DataStreams::PathwayContext.decode_b64(returned_value)
        expect(decoded).to have_attributes(hash: KAFKA_ORDERS_PRODUCE_HASH)
      end

      it 'sets tags on the active_span for that hash' do
        span = instance_double(Datadog::Tracing::SpanOperation)
        allow(Datadog::Tracing).to receive(:active_span).and_return(span)
        expect(span).to receive(:set_tag).with('pathway.hash', KAFKA_ORDERS_PRODUCE_HASH.to_s)

        processor.set_produce_checkpoint(type: 'kafka', destination: 'orders', manual_checkpoint: false)
      end

      it 'advances the pathway context with new hash' do
        initial_hash = processor.pathway_context.hash

        processor.set_produce_checkpoint(type: 'kafka', destination: 'orders')

        expect(processor.pathway_context.hash).not_to eq(initial_hash)
      end

      it 'restarts pathway on consecutive same-direction checkpoints (loop detection)' do
        processor.set_produce_checkpoint(type: 'kafka', destination: 'step1')
        first_pathway_start = processor.pathway_context.pathway_start

        processor.set_produce_checkpoint(type: 'kafka', destination: 'step2')

        expect(processor.pathway_context.pathway_start).not_to eq(first_pathway_start)
        expect(processor.pathway_context.pathway_start).to be >= first_pathway_start
      end
    end

    describe '#set_consume_checkpoint' do
      it 'returns a hash' do
        result = processor.set_consume_checkpoint(type: 'kafka', source: 'orders')
        expect(result).to be_a(String)
        expect(result).not_to be_empty
      end

      it 'computes deterministic hash' do
        processor.set_consume_checkpoint(type: 'kafka', source: 'orders', manual_checkpoint: false)
        expect(processor.pathway_context.hash).to eq(KAFKA_ORDERS_CONSUME_HASH_WITHOUT_CARRIER)
      end

      it 'can get a previous hash from the carrier' do
        # Producer creates context in carrier
        producer = described_class.new(interval: 10.0, logger: logger, settings: settings, agent_settings: agent_settings)
        carrier = {}
        producer.set_produce_checkpoint(type: 'kafka', destination: 'orders', manual_checkpoint: false) do |key, value|
          carrier[key] = value
        end
        produce_hash = producer.pathway_context.hash

        # Consumer reads from carrier
        processor.set_consume_checkpoint(type: 'kafka', source: 'orders', manual_checkpoint: false) do |key|
          carrier[key]
        end

        # Consumer hash is computed from producer hash (parent)
        expect(processor.pathway_context.hash).to eq(KAFKA_ORDERS_CONSUME_HASH)
        expect(processor.pathway_context.hash).not_to eq(produce_hash)

        producer.stop(true)
      end

      it 'sets tags on the active_span for that hash' do
        span = instance_double(Datadog::Tracing::SpanOperation)
        allow(Datadog::Tracing).to receive(:active_span).and_return(span)
        expect(span).to receive(:set_tag).with('pathway.hash', KAFKA_ORDERS_CONSUME_HASH_WITHOUT_CARRIER.to_s)

        processor.set_consume_checkpoint(type: 'kafka', source: 'orders', manual_checkpoint: false)
      end

      it 'handles missing pathway context in carrier gracefully' do
        carrier = {}

        expect do
          processor.set_consume_checkpoint(type: 'kafka', source: 'orders') { |key| carrier[key] }
        end.not_to raise_error
      end
    end

    describe 'pathway context tracking' do
      it 'computes different hashes for different edge types' do
        processor.set_produce_checkpoint(type: 'kafka', destination: 'orders', manual_checkpoint: false)
        expect(processor.pathway_context.hash).to eq(KAFKA_ORDERS_PRODUCE_HASH)

        processor.set_produce_checkpoint(type: 'kinesis', destination: 'orders', manual_checkpoint: false)
        expect(processor.pathway_context.hash).to eq(KINESIS_ORDERS_PRODUCE_HASH)
      end

      it 'computes different hashes for different topics' do
        processor.set_produce_checkpoint(type: 'kafka', destination: 'orders', manual_checkpoint: false)
        expect(processor.pathway_context.hash).to eq(KAFKA_ORDERS_PRODUCE_HASH)

        processor.set_produce_checkpoint(type: 'kafka', destination: 'payments', manual_checkpoint: false)
        expect(processor.pathway_context.hash).to eq(KAFKA_PAYMENTS_PRODUCE_HASH)
      end
    end

    describe 'produce-consume pathway flow' do
      it 'maintains pathway continuity through produce and consume' do
        produce_context = processor.set_produce_checkpoint(type: 'kafka', destination: 'orders')
        produce_hash = processor.pathway_context.hash
        produce_pathway_start = processor.pathway_context.pathway_start

        carrier = {Datadog::DataStreams::Processor::PROPAGATION_KEY => produce_context}

        processor.set_consume_checkpoint(type: 'kafka', source: 'orders') { |key| carrier[key] }
        consume_hash = processor.pathway_context.hash

        expect(consume_hash).not_to eq(produce_hash)
        expect(processor.pathway_context.pathway_start.to_f).to be_within(0.001).of(produce_pathway_start.to_f)
      end
    end

    describe 'internal bucket aggregation' do
      it 'aggregates multiple checkpoints into DDSketch histograms' do
        frozen_time = Time.utc(2000, 1, 1, 0, 0, 0)
        allow(Datadog::Core::Utils::Time).to receive(:now).and_return(frozen_time)
        allow(Datadog::Tracing).to receive(:active_span).and_return(nil)

        processor.stop(true)

        processor.set_produce_checkpoint(type: 'kafka', destination: 'topicA', manual_checkpoint: false)
        processor.set_produce_checkpoint(type: 'kafka', destination: 'topicA', manual_checkpoint: false)
        processor.set_produce_checkpoint(type: 'kafka', destination: 'topicA', manual_checkpoint: false)

        processor.send(:process_events)

        now_ns = (frozen_time.to_f * 1e9).to_i
        bucket_time_ns = now_ns - (now_ns % processor.bucket_size_ns)

        expect(processor.buckets).not_to be_empty, lambda {
          "Expected bucket key: #{bucket_time_ns}, actual keys: #{processor.buckets.keys.inspect}"
        }

        bucket = processor.buckets[bucket_time_ns]
        expect(bucket).not_to be_nil, lambda {
          "Expected bucket: #{bucket_time_ns}, actual: #{processor.buckets.keys.inspect}"
        }

        pathway_stats = bucket[:pathway_stats]
        expect(pathway_stats).not_to be_empty

        aggr_key = pathway_stats.keys.first
        stats = pathway_stats[aggr_key]

        aggregate_failures do
          expect(stats[:edge_latency]).to be_a(Datadog::Core::DDSketch)
          expect(stats[:full_pathway_latency]).to be_a(Datadog::Core::DDSketch)

          expect(stats[:edge_latency].count).to eq(3)
          expect(stats[:full_pathway_latency].count).to eq(3)

          expect(stats[:edge_latency].encode).to be_a(String)
          expect(stats[:edge_latency].encode).not_to be_empty
          expect(stats[:full_pathway_latency].encode).to be_a(String)
          expect(stats[:full_pathway_latency].encode).not_to be_empty
        end
      end
    end
  end

  describe 'Kafka tracking methods' do
    let(:base_time) { Time.now }

    after { processor.stop(true) }

    describe '#track_kafka_produce' do
      it 'tracks produce offset for topic/partition' do
        processor.track_kafka_produce('orders', 0, 100, base_time)
        processor.track_kafka_produce('orders', 0, 101, base_time + 1)

        # Verify offset tracking works (metadata only, no stats sent)
        expect { processor.send(:perform) }.not_to raise_error
      end

      it 'tracks multiple produces to same topic/partition' do
        processor.track_kafka_produce('orders', 0, 100, base_time)
        processor.track_kafka_produce('orders', 0, 101, base_time + 1)
        processor.track_kafka_produce('orders', 0, 102, base_time + 2)

        # Should track latest offset (verified in perform/flush)
        expect { processor.track_kafka_produce('orders', 0, 103, base_time + 3) }.not_to raise_error
      end

      it 'tracks produces to different partitions independently' do
        processor.track_kafka_produce('orders', 0, 100, base_time)
        processor.track_kafka_produce('orders', 1, 200, base_time)
        processor.track_kafka_produce('orders', 2, 300, base_time)

        expect { processor.send(:perform) }.not_to raise_error
      end
    end

    describe '#track_kafka_consume' do
      it 'accepts consume tracking calls without error' do
        expect {
          processor.track_kafka_consume('orders', 0, 100, base_time)
          processor.track_kafka_consume('orders', 0, 101, base_time + 1)
          processor.track_kafka_consume('payments', 1, 50, base_time + 2)
        }.not_to raise_error
      end

      it 'tracks sequential consumption' do
        processor.track_kafka_consume('orders', 0, 100, base_time)
        processor.track_kafka_consume('orders', 0, 101, base_time + 1)
        processor.track_kafka_consume('orders', 0, 102, base_time + 2)

        expect { processor.send(:perform) }.not_to raise_error
      end

      it 'detects gaps in consumption (lag)' do
        processor.track_kafka_consume('orders', 0, 100, base_time)
        # Gap: skipped 101-104
        processor.track_kafka_consume('orders', 0, 105, base_time + 1)

        # Should still track successfully despite gap
        expect { processor.send(:perform) }.not_to raise_error
      end
    end

    describe 'end-to-end Kafka flow' do
      it 'tracks complete produce -> consume lifecycle' do
        # Producer writes message
        processor.track_kafka_produce('orders', 0, 100, base_time)

        # Consumer reads message
        processor.track_kafka_consume('orders', 0, 100, base_time + 1)

        # Should flush without errors
        expect { processor.send(:perform) }.not_to raise_error
      end
    end
  end
end
