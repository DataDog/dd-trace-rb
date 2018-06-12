module Datadog
  module Contrib
    module RestClient
      # RestClient RequestPatch
      module RequestPatch
        def self.included(base)
          base.extend(InstanceMethods)
        end

        # InstanceMethods - implementing instrumentation
        module InstanceMethods
          def execute(&block)
            super
          end
        end
      end
    end
  end
end
