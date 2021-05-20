require 'ddtrace/contrib/patcher'
require 'ddtrace/contrib/rspec/example'

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
          ::RSpec::Core::Example.include(Example)
        end
      end
    end
  end
end
