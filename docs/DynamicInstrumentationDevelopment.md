# Dynamic Instrumentation Development Guide

## Starting the Remote Configuration Worker Manually

Add this to your Rails initializer after `Datadog.configure`:

```ruby
# config/initializers/datadog.rb

Datadog.configure do |c|
  c.dynamic_instrumentation.enabled = true
  # This internal setting should only be used when developing the datadog gem itself and
  # **should not** ever be used outside of that.
  c.dynamic_instrumentation.internal.development = true
  c.remote.enabled = true
  # ... other configuration
end

# Start the RC worker
if Datadog.send(:components).remote
  Datadog.send(:components).remote.start
end
```

Verify in logs:

```
D, [timestamp] DEBUG -- datadog: new remote configuration client: <client_id> products: LIVE_DEBUGGING
```
