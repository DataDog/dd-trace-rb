# typed: true
require 'ddtrace/contrib/registry'

module Datadog
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
    # after the tracer has complete initialization. Use `Datadog::Contrib::REGISTRY` instead
    # of `Datadog.registry` when you code might be called during tracer initialization.
    REGISTRY = Registry.new
  end
end

require 'ddtrace/contrib/action_cable/integration'
require 'ddtrace/contrib/action_pack/integration'
require 'ddtrace/contrib/action_view/integration'
require 'ddtrace/contrib/active_model_serializers/integration'
require 'ddtrace/contrib/active_record/integration'
require 'ddtrace/contrib/active_storage/integration'
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
require 'ddtrace/contrib/httpclient/integration'
require 'ddtrace/contrib/httprb/integration'
require 'ddtrace/contrib/integration'
require 'ddtrace/contrib/kafka/integration'
require 'ddtrace/contrib/lograge/integration'
require 'ddtrace/contrib/mongodb/integration'
require 'ddtrace/contrib/mysql2/integration'
require 'ddtrace/contrib/presto/integration'
require 'ddtrace/contrib/qless/integration'
require 'ddtrace/contrib/que/integration'
require 'ddtrace/contrib/racecar/integration'
require 'ddtrace/contrib/rack/integration'
require 'ddtrace/contrib/rails/integration'
require 'ddtrace/contrib/rake/integration'
require 'ddtrace/contrib/redis/integration'
require 'ddtrace/contrib/resque/integration'
require 'ddtrace/contrib/rest_client/integration'
require 'ddtrace/contrib/semantic_logger/integration'
require 'ddtrace/contrib/sequel/integration'
require 'ddtrace/contrib/shoryuken/integration'
require 'ddtrace/contrib/sidekiq/integration'
require 'ddtrace/contrib/sinatra/integration'
require 'ddtrace/contrib/sneakers/integration'
require 'ddtrace/contrib/sucker_punch/integration'
