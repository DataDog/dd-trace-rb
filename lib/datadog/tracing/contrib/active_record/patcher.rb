# frozen_string_literal: true

require_relative '../patcher'
require_relative 'events'
require_relative 'async_executor/connection_pool'

module Datadog
  module Tracing
    module Contrib
      module ActiveRecord
        # Patcher enables patching of 'active_record' module.
        module Patcher
          include Contrib::Patcher

          module_function

          def target_version
            Integration.version
          end

          def patch
            Events.subscribe!

            if Integration.version >= Gem::Version.new('7.0.0') && ConcurrentRuby::Integration.patchable?
              ::ActiveRecord::ConnectionAdapters::ConnectionPool.prepend(AsyncExecutor::ConnectionPool)
            end
          end
        end
      end
    end
  end
end
