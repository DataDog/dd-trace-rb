# frozen_string_literal: true

# Kafka produce/consume workload for DSM overhead benchmarking.
#
# Implements the canonical cross-language DSM workload (Linear DSM2-590): per
# iteration, a fresh single-partition topic and consumer group; 1000 messages
# with a fixed 1024-byte payload, no key and 5 headers (key0..key4 ->
# value0..value4), produce+flush, then consume with a synchronous commit every
# COMMIT_EVERY messages and after the last one. 1 thread by default
# (NUM_THREADS). All iterations run in one process (see run_timeit.rb).
#
# Tracing/DSM are controlled purely by environment (requiring
# datadog/auto_instrument + DD_DATA_STREAMS_ENABLED, see run_timeit.rb); this
# file contains no tracer-specific code, so the apm-only and apm+dsm
# scenarios run the exact same bytes.

require "kafka"
require "securerandom"

BOOTSTRAP_SERVERS = ENV.fetch("KAFKA_BOOTSTRAP_SERVERS", "localhost:9092")
MESSAGE_COUNT = 1000
NUM_HEADERS = 5
PAYLOAD = ("x" * 1024).freeze
# ruby-kafka sends the whole buffer as one batch per partition (no size-based
# splitting); 1000 x 1 KiB exceeds the broker's ~1 MB default, so deliver in chunks.
PRODUCE_BATCH = 500
# Per-process suffix so topic and group names stay fresh across processes
# sharing a broker (e.g. the three scenarios, or local reruns).
RUN_NONCE = SecureRandom.hex(4)
DEFAULT_COMMIT_EVERY = 100

# COMMIT_EVERY (integer >= 1, default 100): during the timed consume phase,
# commit synchronously after every COMMIT_EVERY consumed messages and always
# after the last one (so 100 gives 10 explicit commits per worker iteration).
# COMMIT_EVERY=1 is the old per-message sync commit, kept as an on-demand
# diagnostic.
def commit_every_from_env
  raw = ENV.fetch("COMMIT_EVERY", DEFAULT_COMMIT_EVERY.to_s)
  # Strict decimal digits: Integer() alone would accept "1_0", " 5" or "+5".
  value = raw.match?(/\A[0-9]+\z/) ? Integer(raw, 10) : nil
  if value.nil? || value < 1
    raise ArgumentError, "COMMIT_EVERY must be an integer >= 1, got #{raw.inspect}"
  end

  value
end

# Raises Kafka::TopicAlreadyExists rather than reusing a topic: every
# iteration must start from a fresh, empty topic.
def create_topics(kafka, topics)
  topics.each do |topic|
    kafka.create_topic(topic, num_partitions: 1, replication_factor: 1)
  end
end

def run_worker(topic, group_id, commit_every)
  kafka = Kafka.new(seed_brokers: [BOOTSTRAP_SERVERS], client_id: "dsm-benchmark", logger: Logger.new(File::NULL))

  headers = NUM_HEADERS.times.each_with_object({}) { |j, h| h["key#{j}"] = "value#{j}" }

  # Setup: not timed. Producer/consumer construction, metadata pre-fetch,
  # subscribe, and forcing the consumer-group join while the topic is still
  # empty all happen before produce_start, so they don't land in
  # produce_ms/consume_ms.
  producer = kafka.producer(required_acks: :all, max_retries: 1, retry_backoff: 0.1)
  # The producer has its own private Cluster; loading the topic's metadata
  # here makes deliver_messages' add_target_topics/refresh a no-op.
  producer.instance_variable_get(:@cluster).partitions_for(topic)
  # interval 0 / threshold 0 turn off ruby-kafka's interval and threshold
  # auto-commits (OffsetManager#commit_timeout_reached? and
  # #commit_threshold_reached? both short-circuit on 0), so the explicit
  # commit_offsets calls below are the commit policy. One automatic commit
  # remains and cannot be configured away: commit_offsets_if_necessary also
  # checks recommit_timeout_reached?, which is true while @last_recommit is
  # nil, so each_message does one recommit (OffsetFetch + OffsetCommit) right
  # after message 1, then none for offset_retention_time / 2 (12h by
  # default). It is the same in every scenario and COMMIT_EVERY mode.
  consumer = kafka.consumer(group_id: group_id, offset_commit_interval: 0, offset_commit_threshold: 0)
  consumer.subscribe(topic)
  # ruby-kafka only joins the group and gets a partition assignment lazily,
  # on the first each_message poll -- otherwise this would land in the
  # timed consume phase. join_group is private; there's no public
  # equivalent to force it early.
  consumer.send(:join_group)
  # Also start+configure the Fetcher's background thread here, while the
  # topic is still empty, and give it a moment to come up. Fetcher#start is
  # a no-op once already running, so the real each_message call below just
  # reuses this thread. Without this, each_message's own first call to
  # Fetcher#start creates the thread with no intervening blocking I/O to
  # yield the GVL, so the foreground can reach fetch_batches's `sleep
  # (@fetcher.max_wait_time)` fallback before the background thread has
  # processed its `configure` command -- sleeping the *default* 1s instead
  # of the 0.01s configured below, adding a spurious ~1s to consume_ms.
  fetcher = consumer.instance_variable_get(:@fetcher)
  fetcher.configure(min_bytes: 1, max_bytes: 10_485_760, max_wait_time: 0.01)
  fetcher.start
  sleep 0.05

  # Phase 1: produce all messages.
  produce_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  MESSAGE_COUNT.times do |i|
    # dup: ruby-kafka keeps the hash by reference and DSM writes its pathway header into it.
    producer.produce(PAYLOAD, topic: topic, headers: headers.dup)
    producer.deliver_messages if ((i + 1) % PRODUCE_BATCH).zero?
  end
  # Final flush; a no-op when the last chunk was already delivered.
  producer.deliver_messages
  produce_ms = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - produce_start) * 1000.0

  # Phase 2: consume all messages, committing synchronously every
  # commit_every messages and after the last one. commit_offsets commits the
  # last marked offset + 1 for the (single) partition.
  consumed = 0
  consume_end = nil
  consume_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  # ruby-kafka defaults to max_wait_time: 1s, which made fetch waits ~3s of a
  # ~3.1s run and swamped the instrumentation cost we're trying to measure
  # (all three scenarios landed within 0.5% of each other). Return as soon as
  # any data is available so the timing reflects per-message work.
  consumer.each_message(min_bytes: 1, max_wait_time: 0.01) do |message|
    consumer.mark_message_as_processed(message)
    consumed += 1
    last_message = consumed >= MESSAGE_COUNT
    consumer.commit_offsets if last_message || (consumed % commit_every).zero?
    if last_message
      # Stop the consume timer here, before `break`: breaking out of
      # each_message runs ruby-kafka's consumer_loop `ensure`, which stops
      # the fetcher, does make_final_offsets_commit! (another OffsetCommit of
      # the offsets just committed above), leaves the group and disconnects.
      # That is teardown and must stay untimed. Results recorded before this
      # change timed that teardown too and are not comparable.
      consume_end = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      break
    end
  end

  raise "Consumed #{consumed}/#{MESSAGE_COUNT} messages on topic #{topic}" if consumed != MESSAGE_COUNT

  consume_ms = (consume_end - consume_start) * 1000.0

  {produce_ms: produce_ms, consume_ms: consume_ms}
ensure
  # Teardown: not timed.
  consumer&.stop
  producer&.shutdown
  kafka&.close
end

# Runs one full multi-threaded produce/consume pass.
#
# +run_id+ (plus RUN_NONCE) makes topic and consumer-group names unique per
# iteration, so every warmup/timed run gets a fresh topic and group.
def run_benchmark(run_id = 0, commit_every: commit_every_from_env)
  base_topic = ENV.fetch("KAFKA_TOPIC", "benchmark-topic")
  thread_count = Integer(ENV.fetch("NUM_THREADS", "1"))

  topics = Array.new(thread_count) { |t| "#{base_topic}-#{RUN_NONCE}-#{run_id}-#{t}" }

  bootstrap_kafka = Kafka.new(seed_brokers: [BOOTSTRAP_SERVERS], client_id: "dsm-benchmark-admin", logger: Logger.new(File::NULL))
  create_topics(bootstrap_kafka, topics)
  bootstrap_kafka.close

  phase_times = []
  errors = []
  mutex = Mutex.new

  threads = topics.map do |topic|
    group_id = "#{topic}-group"
    Thread.new do
      result = run_worker(topic, group_id, commit_every)
      mutex.synchronize { phase_times << result }
    rescue => e
      mutex.synchronize { errors << e }
    end
  end
  threads.each(&:join)

  raise errors.first if errors.any?

  n = phase_times.size.nonzero? || 1
  mean_produce_ms = phase_times.sum { |p| p[:produce_ms] } / n
  mean_consume_ms = phase_times.sum { |p| p[:consume_ms] } / n
  {produce_ms: mean_produce_ms, consume_ms: mean_consume_ms}
end

if __FILE__ == $PROGRAM_NAME
  puts run_benchmark
  puts "Benchmark completed successfully"
end
