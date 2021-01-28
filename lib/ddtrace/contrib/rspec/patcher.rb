require 'ddtrace/contrib/patcher'
require 'ddtrace/contrib/rspec/example'
require 'ddtrace/contrib/rspec/example_group'

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
          ::RSpec::Core::Example.send(:include, Example)
          ::RSpec::Core::ExampleGroup.send(:include, ExampleGroup)
        end
      end
    end
  end
end
