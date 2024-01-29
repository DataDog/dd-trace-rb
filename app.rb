lib = File.expand_path('lib', __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

require 'ddtrace'

Datadog.configure do |c|
  c.service = 'my-ruby-app'
  c.env = 'marco-laptop'
end


Datadog::Tracing.trace('custom-service') do
  Datadog::Tracing.trace('custom-service-child', service: 'custom-service') do

  end
end

Datadog::Tracing.trace('custom-peer') do
  Datadog::Tracing.trace('custom-peer-child', service: 'custom-peer') do |span|
    span.set_tag('span.kind', 'client')
    span.set_tag('peer.service', 'custom-peer-inferred')
  end
end
