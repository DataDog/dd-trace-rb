# Distributed Tracing

Distributed tracing allows traces to be propagated across multiple instrumented applications so that a request can be presented as a single trace, rather than a separate trace per service.

To trace requests across application boundaries, the following must be propagated between each application:

| Property              | Type    | Description                                                                                                                 |
| --------------------- | ------- | --------------------------------------------------------------------------------------------------------------------------- |
| **Trace ID**          | Integer | ID of the trace. This value should be the same across all requests that belong to the same trace.                           |
| **Parent Span ID**    | Integer | ID of the span in the service originating the request. This value will always be different for each request within a trace. |
| **Sampling Priority** | Integer | Sampling priority level for the trace. This value should be the same across all requests that belong to the same trace.     |

Such propagation can be visualized as:

```
Service A:
  Trace ID:  100000000000000001
  Parent ID: 0
  Span ID:   100000000000000123
  Priority:  1

  |
  | Service B Request:
  |   Metadata:
  |     Trace ID:  100000000000000001
  |     Parent ID: 100000000000000123
  |     Priority:  1
  |
  V

Service B:
  Trace ID:  100000000000000001
  Parent ID: 100000000000000123
  Span ID:   100000000000000456
  Priority:  1

  |
  | Service C Request:
  |   Metadata:
  |     Trace ID:  100000000000000001
  |     Parent ID: 100000000000000456
  |     Priority:  1
  |
  V

Service C:
  Trace ID:  100000000000000001
  Parent ID: 100000000000000456
  Span ID:   100000000000000789
  Priority:  1
```

## Over HTTP

For HTTP requests between instrumented applications, this trace metadata is propagated by use of HTTP Request headers:

| Property              | Type    | HTTP Header name              |
| --------------------- | ------- | ----------------------------- |
| **Trace ID**          | Integer | `x-datadog-trace-id`          |
| **Parent Span ID**    | Integer | `x-datadog-parent-id`         |
| **Sampling Priority** | Integer | `x-datadog-sampling-priority` |

Such that:

```
Service A:
  Trace ID:  100000000000000001
  Parent ID: 0
  Span ID:   100000000000000123
  Priority:  1

  |
  | Service B HTTP Request:
  |   Headers:
  |     x-datadog-trace-id:          100000000000000001
  |     x-datadog-parent-id:         100000000000000123
  |     x-datadog-sampling-priority: 1
  |
  V

Service B:
  Trace ID:  100000000000000001
  Parent ID: 100000000000000123
  Span ID:   100000000000000456
  Priority:  1

  |
  | Service C HTTP Request:
  |   Headers:
  |     x-datadog-trace-id:          100000000000000001
  |     x-datadog-parent-id:         100000000000000456
  |     x-datadog-sampling-priority: 1
  |
  V

Service C:
  Trace ID:  100000000000000001
  Parent ID: 100000000000000456
  Span ID:   100000000000000789
  Priority:  1
```

### Using the HTTP propagator

To make the process of propagating this metadata easier, you can use the `Datadog::HTTPPropagator` module.

On the client:

```ruby
Datadog.tracer.trace('web.call') do |span|
  # Inject span context into headers (`env` must be a Hash)
  Datadog::HTTPPropagator.inject!(span.context, env)
end
```

On the server:

```ruby
Datadog.tracer.trace('web.work') do |span|
  # Build a context from headers (`env` must be a Hash)
  context = HTTPPropagator.extract(request.env)
  Datadog.tracer.provider.context = context if context.trace_id
end
```

## Activating distributed tracing for integrations

Many integrations included in `ddtrace` support distributed tracing. Distributed tracing is enabled by default, but can be activated via configuration settings.

- If your application receives requests from services with distributed tracing activated, you must activate distributed tracing on the integrations that handle these requests (e.g. Rails)
- If your application send requests to services with distributed tracing activated, you must activate distributed tracing on the integrations that send these requests (e.g. Faraday)
- If your application both sends and receives requests implementing distributed tracing, it must activate all integrations that handle these requests.

For more details on how to activate distributed tracing for integrations, see their documentation:

- [Excon](https://github.com/DataDog/dd-trace-rb/blob/master/docs/Integrations.md#excon)
- [Faraday](https://github.com/DataDog/dd-trace-rb/blob/master/docs/Integrations.md#faraday)
- [Rest Client](https://github.com/DataDog/dd-trace-rb/blob/master/docs/Integrations.md#restclient)
- [Net/HTTP](https://github.com/DataDog/dd-trace-rb/blob/master/docs/Integrations.md#nethttp)
- [Rack](https://github.com/DataDog/dd-trace-rb/blob/master/docs/Integrations.md#rack)
- [Rails](https://github.com/DataDog/dd-trace-rb/blob/master/docs/Integrations.md#rails)
- [Sinatra](https://github.com/DataDog/dd-trace-rb/blob/master/docs/Integrations.md#sinatra)
