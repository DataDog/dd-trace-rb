# typed: true
module Datadog
  module Contrib
    module ConcurrentRuby
      # ConcurrentRuby integration constants
      # @public_api
      module Ext
        APP = 'concurrent-ruby'.freeze
        SERVICE_NAME = 'concurrent-ruby'.freeze
        ENV_ENABLED = 'DD_TRACE_CONCURRENT_RUBY_ENABLED'.freeze
      end
    end
  end
end
