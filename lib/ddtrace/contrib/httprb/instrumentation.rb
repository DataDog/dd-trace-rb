module Datadog
  module Contrib
    module Httprb
      # Instrumentation for Httprb
      module Instrumentation
        def self.included(base)
          base.send(:prepend, InstanceMethods)
        end

        module InstanceMethods
          def initialize(default_options={})
            
            if default_options[:features] && !default_options[:features][:datadog_wrap]
              default_options[:features][:datadog_wrap] = {}
            end
            
            super(default_options)
          end
        end
      end
    end
  end
end