# frozen_string_literal: true

require_relative "../patcher"
require_relative "ext"
require_relative "instrumentation"

module Datadog
  module Tracing
    module Contrib
      module Rake
        # Patcher enables patching of 'rake' module.
        module Patcher
          include Contrib::Patcher

          def self.target_version
            Integration.version
          end

          def self.patch
            # Add instrumentation patch to Rake task
            ::Rake::Task.include(Instrumentation)
          end

          def self.get_option(option)
            Datadog.configuration.tracing[:rake].get_option(option)
          end
        end
      end
    end
  end
end
