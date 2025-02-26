# frozen_string_literal: true

require_relative 'http/builder'
require_relative 'http/adapters/net'
require_relative 'http/adapters/unix_socket'
require_relative 'http/adapters/test'

module Datadog
  module Core
    module Transport
      module HTTP
        # Helper function that delegates to Builder.new
        # but is under HTTP namespace so that client code requires this file
        # to get the adapters configured, and not the builder directly.
        module_function def build(api_instance_class:, &block)
          Builder.new(api_instance_class: api_instance_class, &block)
        end

        # Add adapters to registry
        Builder::REGISTRY.set(
          Transport::HTTP::Adapters::Net,
          Core::Configuration::Ext::Agent::HTTP::ADAPTER
        )
        Builder::REGISTRY.set(
          Transport::HTTP::Adapters::Test,
          Transport::Ext::Test::ADAPTER
        )
        Builder::REGISTRY.set(
          Transport::HTTP::Adapters::UnixSocket,
          Transport::Ext::UnixSocket::ADAPTER
        )
      end
    end
  end
end
