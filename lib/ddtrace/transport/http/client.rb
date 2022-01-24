# typed: false
require 'datadog/core/transport/http/client'
require 'ddtrace/transport/http/traces'

module Datadog
  module Transport
    module HTTP
      class Client < Core::HTTP::Client
        include Traces::Client
      end
    end
  end
end
