require 'ddtrace/contrib/patcher'
require 'ddtrace/contrib/rspec/instrumentation'

module Datadog
  module Contrib
    module RSpec
      # Patcher enables patching of 'rspec' module.
      module Patcher
        include Contrib::Patcher

        module_function

        def target_version
          Integration.version
        end

        def patch
          ::RSpec::Core::Example.send(:include, Instrumentation::Example)
          ::RSpec::Core::ExampleGroup.send(:include, Instrumentation::ExampleGroup)
        end
      end
    end
  end
end
