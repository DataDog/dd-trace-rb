# typed: true

require 'datadog/tracing'
require 'datadog/tracing/contrib/registry'
require 'datadog/tracing/contrib/extensions'

module Datadog
  module Tracing
    module Contrib
      # Registry is a global, declarative repository of all available integrations.
      #
      # Integrations should register themselves with the registry as early as
      # possible as the initial tracer configuration can only activate integrations
      # if they have already been registered.
      #
      # Despite that, integrations *can* be appended to the registry at any point
      # of the program execution. Newly appended integrations can then be
      # activated during tracer reconfiguration.
      #
      # The registry does not depend on runtime configuration and registered integrations
      # must execute correctly after successive configuration changes.
      # The registered integrations themselves can depend on the stateful configuration
      # of the tracer.
      #
      # `Datadog.registry` is a helper accessor to this constant, but it's only available
      # after the tracer has complete initialization. Use `Datadog::Tracing::Contrib::REGISTRY` instead
      # of `Datadog.registry` when you code might be called during tracer initialization.
      REGISTRY = Registry.new
    end
  end
end

require 'datadog/tracing/contrib/action_cable/integration'
require 'datadog/tracing/contrib/action_mailer/integration'
require 'datadog/tracing/contrib/action_pack/integration'
require 'datadog/tracing/contrib/action_view/integration'
require 'datadog/tracing/contrib/active_model_serializers/integration'
require 'datadog/tracing/contrib/active_job/integration'
require 'datadog/tracing/contrib/active_record/integration'
require 'datadog/tracing/contrib/active_support/integration'
require 'datadog/tracing/contrib/aws/integration'
require 'datadog/tracing/contrib/concurrent_ruby/integration'
require 'datadog/tracing/contrib/dalli/integration'
require 'datadog/tracing/contrib/delayed_job/integration'
require 'datadog/tracing/contrib/elasticsearch/integration'
require 'datadog/tracing/contrib/ethon/integration'
require 'datadog/tracing/contrib/excon/integration'
require 'datadog/tracing/contrib/faraday/integration'
require 'datadog/tracing/contrib/grape/integration'
require 'datadog/tracing/contrib/graphql/integration'
require 'datadog/tracing/contrib/grpc/integration'
require 'datadog/tracing/contrib/http/integration'
require 'datadog/tracing/contrib/httpclient/integration'
require 'datadog/tracing/contrib/httprb/integration'
require 'datadog/tracing/contrib/integration'
require 'datadog/tracing/contrib/kafka/integration'
require 'datadog/tracing/contrib/lograge/integration'
require 'datadog/tracing/contrib/mongodb/integration'
require 'datadog/tracing/contrib/mysql2/integration'
require 'datadog/tracing/contrib/pg/integration'
require 'datadog/tracing/contrib/presto/integration'
require 'datadog/tracing/contrib/qless/integration'
require 'datadog/tracing/contrib/que/integration'
require 'datadog/tracing/contrib/racecar/integration'
require 'datadog/tracing/contrib/rack/integration'
require 'datadog/tracing/contrib/rails/integration'
require 'datadog/tracing/contrib/rake/integration'
require 'datadog/tracing/contrib/redis/integration'
require 'datadog/tracing/contrib/resque/integration'
require 'datadog/tracing/contrib/rest_client/integration'
require 'datadog/tracing/contrib/semantic_logger/integration'
require 'datadog/tracing/contrib/sequel/integration'
require 'datadog/tracing/contrib/shoryuken/integration'
require 'datadog/tracing/contrib/sidekiq/integration'
require 'datadog/tracing/contrib/sinatra/integration'
require 'datadog/tracing/contrib/sneakers/integration'
require 'datadog/tracing/contrib/sucker_punch/integration'
