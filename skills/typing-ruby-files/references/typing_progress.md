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

## Deferred / Known blockers

| File | Errors | Reason deferred |
|------|--------|-----------------|
| `lib/datadog/appsec/contrib/rack/request_middleware.rb` | 34 | Missing AppSec stubs, complex control flow |
| `lib/datadog/tracing/contrib/rack/middlewares.rb` | 27 | Missing tracing stubs, many unresolved constants |
| `lib/datadog/appsec/contrib/devise/tracking_middleware.rb` | 20 | Missing Devise/Warden stubs |
| `lib/datadog/tracing/contrib/sinatra/tracer_middleware.rb` | 11 | Missing Sinatra stubs |
| `lib/datadog/tracing/contrib/rack/trace_proxy_middleware.rb` | 6 | Missing constants (SpanKind::TAG_PROXY), block issues |
