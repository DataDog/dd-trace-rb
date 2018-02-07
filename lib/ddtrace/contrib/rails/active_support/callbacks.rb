require 'ddtrace/contrib/rails/active_support/callbacks/rails50'
require 'ddtrace/contrib/rails/active_support/callbacks/rails51'

module Datadog
  module Contrib
    module Rails
      module ActiveSupport
        # Includes correct Callbacks module
        module Callbacks
          def self.included(base)
            begin
              # 5.1.x only
              if ::Rails.version >= '5.1' && ::Rails.version < '5.2'
                base.include(Rails51)
              # 5.0.x only
              elsif ::Rails.version >= '5.0' && ::Rails.version < '5.1'
                base.include(Rails50)
              end
            rescue StandardError => e
              Datadog::Tracer.log.error("Unable to patch ActiveSupport callbacks: #{e}")
            end
          end
        end
      end
    end
  end
end
