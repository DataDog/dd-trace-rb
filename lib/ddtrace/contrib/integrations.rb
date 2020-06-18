require 'set'
require 'ddtrace/contrib/registerable'

module Datadog
  module Contrib
    extend Registerable::ClassMethods # TODO too broad scope

    def self.register_lazy_integrations
      register_as_lazy :action_cable
      register_as_lazy :action_pack
      register_as_lazy :action_view
      register_as_lazy :active_model_serializers
      register_as_lazy :active_record
      register_as_lazy :active_support
      register_as_lazy :aws
      register_as_lazy :concurrent_ruby
      register_as_lazy :dalli
      register_as_lazy :delayed_job
      register_as_lazy :elasticsearch
      register_as_lazy :ethon
      register_as_lazy :excon
      register_as_lazy :faraday
      register_as_lazy :grape
      register_as_lazy :graphql
      register_as_lazy :grpc
      register_as_lazy :http, class: 'Datadog::Contrib::HTTP::Integration'
      register_as_lazy :integration
      register_as_lazy :presto
      register_as_lazy :mysql2
      register_as_lazy :mongodb
      register_as_lazy :racecar
      register_as_lazy :rack
      register_as_lazy :rails
      register_as_lazy :rake
      register_as_lazy :redis
      register_as_lazy :resque
      register_as_lazy :rest_client
      register_as_lazy :sequel
      register_as_lazy :shoryuken
      register_as_lazy :sidekiq
      register_as_lazy :sinatra
      register_as_lazy :sucker_punch
    end

    self.register_lazy_integrations
  end
end
