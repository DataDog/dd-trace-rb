require 'thread'

# During development, we load `ddtrace` by through `ddtrace.gemspec`,
# which in turn eager loads 'ddtrace/version'.
#
# Users load this gem by requiring this file.
# We need to ensure that any files loaded in our gemspec are also loaded here.
require 'ddtrace/version'

require 'ddtrace/pin'
require 'ddtrace/tracer'
require 'ddtrace/error'
require 'ddtrace/quantization/hash'
require 'ddtrace/quantization/http'
require 'ddtrace/pipeline'
require 'ddtrace/configuration'
require 'ddtrace/patcher'
require 'ddtrace/augmentation'
require 'ddtrace/metrics'

# \Datadog global namespace that includes all tracing functionality for Tracer and Span classes.
module Datadog
  extend Augmentation
  extend Configuration

  # Load and extend Contrib by default
  require 'ddtrace/contrib/extensions'
  extend Contrib::Extensions

  # Load and extend OpenTelemetry compatibility by default
  require 'ddtrace/opentelemetry/extensions'
  extend OpenTelemetry::Extensions

  # Add shutdown hook:
  # Ensures the tracer has an opportunity to flush traces
  # and cleanup before terminating the process.
  at_exit { Datadog.shutdown! }
end

require 'ddtrace/contrib/action_cable/integration'
require 'ddtrace/contrib/action_pack/integration'
require 'ddtrace/contrib/action_view/integration'
require 'ddtrace/contrib/active_model_serializers/integration'
require 'ddtrace/contrib/active_record/integration'
require 'ddtrace/contrib/active_support/integration'
require 'ddtrace/contrib/aws/integration'
require 'ddtrace/contrib/concurrent_ruby/integration'
require 'ddtrace/contrib/dalli/integration'
require 'ddtrace/contrib/delayed_job/integration'
require 'ddtrace/contrib/elasticsearch/integration'
require 'ddtrace/contrib/ethon/integration'
require 'ddtrace/contrib/excon/integration'
require 'ddtrace/contrib/faraday/integration'
require 'ddtrace/contrib/grape/integration'
require 'ddtrace/contrib/graphql/integration'
require 'ddtrace/contrib/grpc/integration'
require 'ddtrace/contrib/http/integration'
require 'ddtrace/contrib/integration'
require 'ddtrace/contrib/presto/integration'
require 'ddtrace/contrib/mysql2/integration'
require 'ddtrace/contrib/mongodb/integration'
require 'ddtrace/contrib/racecar/integration'
require 'ddtrace/contrib/rack/integration'
require 'ddtrace/contrib/rails/integration'
require 'ddtrace/contrib/rake/integration'
require 'ddtrace/contrib/redis/integration'
require 'ddtrace/contrib/resque/integration'
require 'ddtrace/contrib/rest_client/integration'
require 'ddtrace/contrib/sequel/integration'
require 'ddtrace/contrib/shoryuken/integration'
require 'ddtrace/contrib/sidekiq/integration'
require 'ddtrace/contrib/sinatra/integration'
require 'ddtrace/contrib/sucker_punch/integration'
require 'ddtrace/monkey'


GOOD = 'GOOD'