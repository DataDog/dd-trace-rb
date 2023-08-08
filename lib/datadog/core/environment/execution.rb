# frozen_string_literal: true

module Datadog
  module Core
    module Environment
      # Provides information about the execution environment on the current process.
      module Execution
        class << self
          # Is this process running in a development environment?
          # This can be used to make decisions about when to enable
          # background systems like worker threads or telemetry.
          def development?
            !!(repl? || test?)
          end

          private

          # Is this process running a test?
          def test?
            rspec? || minitest?
          end

          # Is this process running inside on a Read–eval–print loop?
          # DEV: REPLs always set the program name to the exact REPL name.
          def repl?
            REPL_PROGRAM_NAMES.include?($PROGRAM_NAME)
          end

          REPL_PROGRAM_NAMES = %w[irb pry].freeze
          private_constant :REPL_PROGRAM_NAMES

          # RSpec always runs using the `rspec` file https://github.com/rspec/rspec-core/blob/main/exe/rspec.
          def rspec?
            $PROGRAM_NAME.end_with?(RSPEC_PROGRAM_NAME)
          end

          RSPEC_PROGRAM_NAME = '/rspec'
          private_constant :RSPEC_PROGRAM_NAME

          # Check if Minitest is present and installed to run.
          def minitest?
            defined?(::Minitest) &&
              ::Minitest.class_variable_defined?(:@@installed_at_exit) &&
              ::Minitest.class_variable_get(:@@installed_at_exit)
          end
        end
      end
    end
  end
end
