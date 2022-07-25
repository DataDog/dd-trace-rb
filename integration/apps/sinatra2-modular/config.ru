require 'ddtrace'
require_relative 'app/acme'

use Datadog::Tracing::Contrib::Rack::TraceMiddleware

run Acme
