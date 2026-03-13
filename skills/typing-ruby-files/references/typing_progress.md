# Typing Progress

## Open PRs

### PR #5438 — Add typing for Socket.hostname
- Branch: `marcotc/type-socket-hostname`
- Files typed: `sig/datadog/core/environment/socket.rbs`
- Changes: Typed `hostname` return as `String`

### PR #5439 — Add typing for Core::Utils::Base64
- Branch: `marcotc/type-base64-decode`
- Files typed: `sig/datadog/core/utils/base64.rbs`
- Changes: Typed `strict_decode64` return as `String`

### PR #5440 — Add shared Rack types for middleware
- Branch: `marcotc/type-appsec-response-to-rack`
- Shared types added: `Rack::env`, `Rack::response`, `Rack::app` in `vendor/rbs/rack/0/rack.rbs`
- Files typed:
  - `sig/datadog/appsec/response.rbs` — `to_rack` returns `Rack::response`
  - `sig/datadog/appsec/contrib/rack/request_middleware.rbs` — full Rack types
  - `sig/datadog/appsec/contrib/rack/request_body_middleware.rbs` — full Rack types + inline assertion
  - `sig/datadog/appsec/contrib/rails/request_middleware.rbs` — full Rack types
  - `sig/datadog/appsec/contrib/sinatra/request_middleware.rbs` — replaced local aliases with shared types
  - `sig/datadog/appsec/contrib/devise/tracking_middleware.rbs` — full Rack types
  - `sig/datadog/tracing/contrib/rack/middlewares.rbs` — full Rack types for TraceMiddleware
  - `sig/datadog/tracing/contrib/rails/middlewares.rbs` — full Rack types for ExceptionMiddleware
  - `sig/datadog/tracing/contrib/sinatra/tracer_middleware.rbs` — full Rack types
  - `sig/datadog/tracing/contrib/hanami/action_tracer.rbs` — full Rack types + `@action: untyped` (TODO: Hanami stub)
  - `sig/datadog/tracing/contrib/hanami/router_tracing.rbs` — full Rack types
- Runtime code changed:
  - `lib/datadog/appsec/contrib/rack/request_body_middleware.rb` — inline Steep type assertions
  - `lib/datadog/tracing/contrib/hanami/router_tracing.rb` — local variable for type narrowing
- Steepfile ignores removed:
  - `lib/datadog/tracing/contrib/rails/middlewares.rb`
  - `lib/datadog/tracing/contrib/hanami/action_tracer.rb`
  - `lib/datadog/tracing/contrib/hanami/router_tracing.rb`

### PR #5441 — Add typing for Core::Environment stats modules
- Branch: `marcotc/type-core-environment-stats`
- Files typed:
  - `sig/datadog/core/environment/class_count.rbs` — `value -> Integer`, `available? -> bool`
  - `sig/datadog/core/environment/gc.rbs` — `stat -> Hash[Symbol, Integer]`, `available? -> bool?`
  - `sig/datadog/core/environment/thread_count.rbs` — `value -> Integer`, `available? -> bool`

### PR #5442 — Add typing for AppSec::Extensions and Gateway::Watcher
- Branch: `marcotc/type-appsec-simple`
- Files typed:
  - `sig/datadog/appsec/extensions.rbs` — `activate! -> void`
  - `sig/datadog/appsec/monitor/gateway/watcher.rbs` — `watch -> void`

### PR #5443 — Add typing for Core::VariableHelpers and Core::Chunker
- Branch: `marcotc/type-core-env-utils`
- Files typed:
  - `sig/datadog/core/environment/variable_helpers.rbs` — `env_to_bool` takes `String | Array[String]`, returns `bool?`; `decode_array` returns `String?`
  - `sig/datadog/core/chunker.rbs` — `chunk_by_size` takes `Array[untyped]` + `Numeric`, returns `Enumerator[Array[untyped], untyped]`

### PR #5444 — Add typing for Buffer::CRuby, HeaderCollection, and SafeDup
- Branch: `marcotc/type-core-buffer-utils`
- Files typed:
  - `sig/datadog/core/buffer/cruby.rbs` — `FIXNUM_MAX: Integer`
  - `sig/datadog/core/header_collection.rbs` — `from_hash` and `initialize` typed as `Hash[String, String]`
  - `sig/datadog/core/utils/safe_dup.rbs` — `frozen_dup` typed as `[T < Object?] (T v) -> T`
- Runtime code changed:
  - `lib/datadog/core/utils/safe_dup.rb` — added `# steep:ignore MethodBodyTypeMismatch` (same Steep issue as `frozen_or_dup`)

### PR #5451 — Add typing for Remote::Dispatcher and Telemetry Worker/Events
- Branch: `marcotc/type-core-remote-telemetry`
- Files typed:
  - `sig/datadog/core/remote/dispatcher.rbs` — `dispatch -> void`
  - `sig/datadog/core/telemetry/event/app_dependencies_loaded.rbs` — `payload: { dependencies: Array[Hash[Symbol, String]] }`
  - `sig/datadog/core/telemetry/worker.rbs` — `buffer_klass -> singleton(Core::Buffer::Random)`

### PR #5452 — Add typing for AppSec::SecurityEngine::Runner#try_run
- Branch: `marcotc/type-appsec-engine-patches`
- Files typed:
  - `sig/datadog/appsec/security_engine/runner.rbs` — `try_run` timeout: `untyped` → `::Integer`

### PR #5453 — Add typing for core utils, encoding, and AppSec::CompressedJson
- Branch: `marcotc/type-core-utils-misc`
- Files typed:
  - `sig/datadog/core/utils/only_once.rbs` — `initialize` → `void`, `ran?` → `bool`, `reset_ran_once_state_for_tests` → `void`
  - `sig/datadog/core/utils/sequence.rbs` — `initialize` → `void`, `next` → `::Integer`
  - `sig/datadog/core/tag_normalizer.rbs` — `normalize`/`normalize_process_value` accept `any` (calls `.to_s`)
  - `sig/datadog/core/encoding.rbs` — `encode`/`decode` use `any` (intentionally open), `join` uses `::Array[::String]`, `::` prefixes
  - `sig/datadog/appsec/compressed_json.rbs` — `dump` accepts `any` payload

### PR #5454 — Add typing for environment stats and LRUCache
- Branch: `marcotc/type-core-env-misc`
- Files typed:
  - `sig/datadog/core/environment/socket.rbs` — `hostname` → `::String`
  - `sig/datadog/core/environment/vm_cache.rbs` — `available?` → `bool?`
  - `sig/datadog/core/environment/yjit.rbs` — `available?` → `bool?`
  - `sig/datadog/core/utils/lru_cache.rbs` — `@store`/`[]`/`[]=` use `any`

### PR #5455 — Add typing for Base64, TagBuilder, and Workers::Polling#stop
- Branch: `marcotc/type-core-misc-utils`
- Files typed:
  - `sig/datadog/core/utils/base64.rbs` — `::` prefixes; `strict_decode64` arg typed as `::String`
  - `sig/datadog/core/tag_builder.rbs` — `::` prefixes; `tags` accepts `any` settings
  - `sig/datadog/core/workers/polling.rbs` — `stop` → `bool`

### PR #5456 — Add typing for AppSec::Response#to_rack, HashCoercion, and Forking
- Branch: `marcotc/type-appsec-core-small`
- Files typed:
  - `sig/datadog/appsec/response.rbs` — `to_rack` → `[::Integer, ::Hash[::String, ::String], ::Array[::String]]`
  - `sig/datadog/appsec/utils/hash_coercion.rbs` — parameter/hash types use `any`
  - `sig/datadog/core/utils/forking.rbs` — `included`/`extended` use `::Module` + `void`

## Deferred / Known blockers

| File | Errors | Reason deferred |
|------|--------|-----------------|
| `lib/datadog/appsec/contrib/rack/request_middleware.rb` | 34 | Missing AppSec stubs, complex control flow |
| `lib/datadog/tracing/contrib/rack/middlewares.rb` | 27 | Missing tracing stubs, many unresolved constants |
| `lib/datadog/appsec/contrib/devise/tracking_middleware.rb` | 20 | Missing Devise/Warden stubs |
| `lib/datadog/tracing/contrib/sinatra/tracer_middleware.rb` | 11 | Missing Sinatra stubs |
| `lib/datadog/tracing/contrib/rack/trace_proxy_middleware.rb` | 6 | Missing constants (SpanKind::TAG_PROXY), block issues |
