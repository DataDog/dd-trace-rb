# typed: true
module Datadog
  module Contrib
    module ConcurrentRuby
      # ConcurrentRuby integration constants
      module Ext
        APP = 'concurrent-ruby'.freeze
        ENV_ENABLED = 'DD_TRACE_CONCURRENT_RUBY_ENABLED'.freeze
      end
    end
  end
end
