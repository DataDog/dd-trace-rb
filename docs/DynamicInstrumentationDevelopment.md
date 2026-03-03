# Dynamic Instrumentation Development Guide

## Starting the Remote Configuration Worker Manually

Add this to your Rails initializer after `Datadog.configure`:

```ruby
# config/initializers/datadog.rb

Datadog.configure do |c|
  c.dynamic_instrumentation.enabled = true
  # In development environments also set:
  c.remote.enabled = true
  c.dynamic_instrumentation.internal.development = true
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
