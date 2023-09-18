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
            !!(webmock_enabled? || repl? || test? || rails_development?)
          end

          # WebMock stores the reference to `Net::HTTP` with constant `OriginalNetHTTP`, and when WebMock enables,
          # the adapter swaps `Net::HTTP` reference to its mock object, @webMockNetHTTP.
          #
          # Hence, we can detect by
          #   1. Checking if `Net::HTTP` is referring to mock object
          #   => ::Net::HTTP.equal?(::WebMock::HttpLibAdapters::NetHttpAdapter.instance_variable_get(:@webMockNetHTTP))
          #
          #   2. Checking if `Net::HTTP` is referring to the original one
          #   => ::Net::HTTP.equal?(::WebMock::HttpLibAdapters::NetHttpAdapter::OriginalNetHTTP)
          def webmock_enabled?
            defined?(::WebMock::HttpLibAdapters::NetHttpAdapter) &&
              defined?(::Net::HTTP) &&
              ::Net::HTTP.equal?(::WebMock::HttpLibAdapters::NetHttpAdapter.instance_variable_get(:@webMockNetHTTP))
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

          # RSpec always runs using the `rspec` file https://github.com/rspec/rspec-core/blob/main/exe/rspec
          def rspec?
            $PROGRAM_NAME.end_with?(RSPEC_PROGRAM_NAME)
          end

          RSPEC_PROGRAM_NAME = '/rspec'
          private_constant :RSPEC_PROGRAM_NAME

          # Check if Minitest is present and installed to run.
          def minitest?
            # Minitest >= 5
            (defined?(::Minitest) &&
              ::Minitest.class_variable_defined?(:@@installed_at_exit) &&
              ::Minitest.class_variable_get(:@@installed_at_exit)) ||
              # Minitest < 5
              (defined?(::Minitest::Unit) &&
                ::Minitest::Unit.class_variable_defined?(:@@installed_at_exit) &&
                ::Minitest::Unit.class_variable_get(:@@installed_at_exit))
          end

          # A Rails Spring Ruby process is a bit peculiar: the process is agnostic
          # whether the application is running as a console or server.
          # Luckily, the Spring gem *must not* be installed in a production environment so
          # detecting its presence is enough to deduct if this is a development environment.
          #
          # @see https://github.com/rails/spring/blob/48b299348ace2188444489a0c216a6f3e9687281/README.md?plain=1#L204-L207
          def rails_development?
            defined?(::Spring)
          end
        end
      end
    end
  end
end
