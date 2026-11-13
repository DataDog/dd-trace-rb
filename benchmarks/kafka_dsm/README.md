# kafka_dsm

Kafka produce/consume workload used to measure how much Data Streams Monitoring (DSM) adds on top
of APM. `kafka_dsm.rb` (workload) and `run_timeit.rb` (timing harness) have no scenario-specific
code; `run.sh` selects the scenario. The client is `ruby-kafka`, the one dd-trace-rb's `kafka`
integration instruments.

Each iteration: create a fresh single-partition topic and consumer group; (untimed) build the
producer and consumer, pre-fetch producer metadata, join the group and wait for the assignment;
(timed) produce 1000 unkeyed messages (`"x" * 1024`, headers `key0..key4` -> `value0..value4`) and
flush; (timed) consume them with a synchronous `commit_offsets` every `COMMIT_EVERY` messages and
after the last one; (untimed) consumer stop/close, then sample process RSS. Duration per iteration =
produce + consume.

ruby-kafka specifics:

- It sends the whole buffer as one batch per partition, and 1000 x 1 KiB exceeds the broker's
  ~1 MB default limit, so the produce loop calls `deliver_messages` every 500 messages
  (`PRODUCE_BATCH`) inside the timed phase.
- The consumer disables interval/threshold auto-commits (`offset_commit_interval: 0,
  offset_commit_threshold: 0`). One recommit that ruby-kafka 1.5.0 can't turn off still runs after
  message 1 of every iteration, so a timed iteration makes `ceil(1000 / COMMIT_EVERY) + 1`
  OffsetCommits.
- The consume timer stops right after the last message's commit, before `break`: leaving
  `each_message` runs ruby-kafka's exit path (fetcher stop, final commit, group leave), which is
  teardown.

## Run

```
./run.sh <baseline|apm-only|apm+dsm> [slug]
```

- `baseline`: `datadog` is not in the bundle and not loaded.
- `apm-only`: `require "datadog/auto_instrument"`, `DD_DATA_STREAMS_ENABLED=false`.
- `apm+dsm`: `require "datadog/auto_instrument"`, `DD_DATA_STREAMS_ENABLED=true`. File/topic slug:
  `apm-plus-dsm`.

The workload gems are pinned in `Gemfile` and locked in `Gemfile.lock`, installed frozen. The tracer
scenarios use `Gemfile.tracer`, which adds the `datadog` gem of the checkout containing this folder
(`path: "../.."`), so the script works from any worktree. Its lockfile follows the checkout, so
`run.sh` derives `Gemfile.tracer.lock` from `Gemfile.lock` on each run and fails if any shared gem
version changed.

Bundler doesn't build native extensions for path gems, so for the tracer scenarios `run.sh` compiles
`ext/libdatadog_api` (DSM needs it) out of tree under `tmp/kafka_dsm/` and copies it to `lib/`,
before anything is timed. It fails if `extconf.rb` skips the build or the extension doesn't load,
and `run_timeit.rb` fails after warmup if `Datadog::DataStreams.enabled?` doesn't match
`DD_DATA_STREAMS_ENABLED`.

Requires Ruby with headers and a C toolchain, Kafka on `localhost:9092` and an endpoint that accepts
the tracer's payloads, such as a Datadog Agent or a mock agent (`DD_TRACE_AGENT_URL`, default
`http://127.0.0.1:18127`). A dead port adds connection-error overhead to the tracer scenarios.

## Environment

| Variable | Default | |
|---|---|---|
| `COMMIT_EVERY` | 100 | sync commit every N messages; integer >= 1 |
| `NUM_THREADS` | 1 | 1 thread is the canonical setup |
| `WARMUP` / `COUNT` | 5 / 25 | discarded / timed iterations (`WARMUP` >= 0, `COUNT` >= 1) |
| `KAFKA_BOOTSTRAP_SERVERS` | `localhost:9092` | |
| `KAFKA_TOPIC` | `benchmark-topic-ruby-<scenario-slug>-<slug>` | base name; run id and iteration are appended |
| `OUT_DIR` | `out/` in this folder | default directory for the output below |
| `EXPERIMENT_NAME` | `<scenario-slug>` | `name` in the result JSON |
| `TIMEIT_OUTPUT` | `$OUT_DIR/ruby-<slug>.<scenario-slug>.json` | result JSON (see below) |

CI: `.gitlab/benchmarks/dsm-throughput.yml` runs this on benchmarking-platform branch
`ruby/data-streams-monitoring` against the pipeline's checkout (automatic on `master`, manual
elsewhere).

## Output

`TIMEIT_OUTPUT` holds one result per scenario, over the timed iterations:

```
[{"median": <duration ms>, "metrics": {
  "process.internal_duration_ms.median": <ms>, "process.internal_duration_ms.std_err": <ms>,
  "process.rss_bytes.median": <bytes>, "phase.produce_ms.median": <ms>,
  "phase.consume_ms.median": <ms>, "config.commit_every": <int>,
  "process.iteration_wall_ms.median": <ms, whole iteration incl. setup/teardown, context only>},
  "name": <EXPERIMENT_NAME>, "warmUpCount": <WARMUP>, "count": <COUNT>,
  "data": [{"status": "Passed", "metrics": {"process.internal_duration_ms": <ms>,
    "process.corrected_duration_ms": <ms, iteration wall>, "runtime.dotnet.mem.committed": <RSS bytes>}},
    ... one per timed iteration]}]
```

`data` feeds the benchmarking-platform's TimeItSharp converter, which expects TimeItSharp's metric
names (it maps `runtime.dotnet.mem.committed` to RSS for every runtime).

RSS is the current RSS (`get_process_mem` gem).
