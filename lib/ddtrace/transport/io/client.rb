# typed: false
require 'datadog/core/transport/io/client'
require 'ddtrace/transport/io/traces'

module Datadog
  module Transport
    module IO
      class Client < Core::IO::Client
        include Traces::Client
      end
    end
  end
end
