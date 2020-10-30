require 'ddtrace/contrib/cucumber/formatter'

module Datadog
  module Contrib
    module Cucumber
      # Instrumentation for Cucumber
      module Instrumentation
        def self.included(base)
          base.send(:prepend, InstanceMethods)
        end

        # Instance methods for configuration
        module InstanceMethods
          attr_reader :datadog_formatter

          def formatters
            @datadog_formatter ||= Datadog::Contrib::Cucumber::Formatter.new(@configuration)
            [@datadog_formatter] + super
          end
        end
      end
    end
  end
end
