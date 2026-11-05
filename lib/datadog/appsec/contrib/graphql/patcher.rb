# frozen_string_literal: true

require_relative "gateway/watcher"

if Gem.loaded_specs["graphql"] && Gem.loaded_specs["graphql"].version >= Gem::Version.new("2.0.19")
  require_relative "appsec_trace"
end

module Datadog
  module AppSec
    module Contrib
      module GraphQL
        # Patcher for AppSec on GraphQL
        module Patcher
          def self.patched?
            Patcher.instance_variable_get(:@patched)
          end

          def self.target_version
            Integration.version
          end

          def self.patch
            Gateway::Watcher.watch
            ::GraphQL::Schema.trace_with(AppSecTrace)
            Patcher.instance_variable_set(:@patched, true)
          end
        end
      end
    end
  end
end
