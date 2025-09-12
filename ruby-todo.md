# Data Streams Monitoring Checkpointer Implementation

## Overview
We'll implement DSM checkpointing for Ruby, following the Python implementation pattern. This system tracks data flow through services and message brokers, enabling monitoring of data pathways (e.g., Service → Kafka → Service → Kafka → Service).

## Python Implementation Reference
Key files in dd-trace-py:
- `processor.py`: Core DSM processor implementation
- `encoding.py`: Handles pathway context encoding/decoding
- `fnv.py`: FNV hash implementation for pathway hashing
- `kafka.py`: Kafka-specific instrumentation

Core components:
1. `DataStreamsProcessor`: Main class that aggregates and reports pathway stats
2. `DataStreamsCtx`: Represents pathway context and handles checkpointing
3. `DsmPathwayCodec`: Handles encoding/decoding of pathway context in message headers

## Implementation Plan

### Phase 1: Karafka Integration Foundation
- [x] PIVOT: Switch from ruby-kafka to Karafka (existing instrumentation available)
- [x] Analyze existing Karafka Monitor and MessagesPatch patterns
- [ ] Create test structure for Karafka DSM instrumentation
- [ ] Leverage existing `lib/datadog/tracing/data_streams/` structure
- [ ] Create Karafka consumer test cases (producer strategy TBD)

### Phase 2: Core Pathway Context
- [ ] Test-drive FNV hashing implementation
- [ ] Test-drive VarInt encoding/decoding
- [ ] Implement DataStreamsCtx with tests
- [ ] Add pathway context encoding/decoding tests
- [ ] Implement header propagation for Kafka

### Phase 3: Checkpointing & Stats
- [ ] Test-drive checkpoint creation and tracking
- [ ] Implement pathway stats collection with tests
- [ ] Add latency tracking (edge and full pathway)
- [ ] Add Kafka offset tracking
- [ ] Implement loop detection logic

### Phase 4: Agent Communication
- [ ] Test-drive stats serialization
- [ ] Implement agent communication layer
- [ ] Add periodic flushing mechanism
- [ ] Implement error handling and retries

### Phase 5: Perfect Karafka Integration
- [ ] Integration testing with real Karafka gem (not mocked classes)
- [ ] Performance testing with DSM overhead measurement
- [ ] Configuration options for DSM tuning (flush intervals, sampling, etc.)
- [ ] Error handling and graceful degradation
- [ ] Memory usage optimization and thread safety validation
- [ ] Real Karafka app integration testing

### Phase 6: Additional Features & Hardening
- [ ] DDSketch implementation for latency distributions
- [ ] Advanced stats aggregation and sampling
- [ ] Agent communication optimization (retries, batching)
- [ ] Live Kafka integration testing

### Phase 7: Producer Integration (WaterDrop) - FUTURE
- [ ] Create WaterDrop integration for DSM producer instrumentation
- [ ] Instrument WaterDrop's monitoring hooks (message.produced_async, etc.)
- [ ] Add DSM context injection into message headers during production
- [ ] Track produce offsets for DSM stats
- [ ] Test WaterDrop DSM integration with Karafka consumers

## Key Implementation Notes
1. The Python implementation uses thread-local storage for context - we'll need to adapt this for Ruby's threading model
2. Pathway context is propagated via message headers in base64 format
3. Stats are collected in time-based buckets and periodically flushed to the agent
4. The system handles both edge latency (between checkpoints) and full pathway latency
5. Loop detection prevents infinite pathway growth when messages loop through topics

## Producer Architecture Notes
- Karafka is consumer-focused; it uses WaterDrop gem for message production
- WaterDrop has excellent monitoring hooks (message.produced_async) perfect for DSM
- Current Karafka integration only covers consumers - WaterDrop integration needed for complete DSM
- Many Karafka users access producers via Karafka.producer or consumer convenience methods

## Python Implementation Details to Remember
1. Pathway context format:
   - 8 bytes: hash value (little-endian)
   - VarInt: pathway start time (milliseconds)
   - VarInt: current edge start time (milliseconds)

2. Stats aggregation:
   - Uses time-based buckets (default 10s)
   - Tracks both produce and commit offsets for Kafka
   - Uses DDSketch for latency distributions

3. Configuration:
   - Agent endpoint: `/v0.1/pipeline_stats`
   - Default flush interval: 10 seconds
   - Gzip compression for payloads
   - Retry mechanism with fibonacci backoff
