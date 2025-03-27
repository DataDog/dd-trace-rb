# frozen_string_literal: true

module Datadog
  module Core
    module Errortracking
      module RequireHooks
        @to_instrument_modules = {}

        def require(path)
          RequireHooks.instance_variable_get(:@to_instrument_modules).each do |module_to_instr|
            next unless path.start_with?(module_to_instr)

            caller_path = caller_locations(1, 1)[0].absolute_path
            absolute_path = File.expand_path(path, File.dirname(caller_path))
            self.class._add_instrument_file("#{absolute_path}.rb")
          end
          super(path)
        end

        def require_relative(path)
          caller_path = caller_locations(1, 1)[0].absolute_path
          absolute_path = File.expand_path(path, File.dirname(caller_path))
          RequireHooks.instance_variable_get(:@to_instrument_modules).each do |module_to_instr|
            Component._add_instrumented_file("#{absolute_path}.rb") if path.start_with?(module_to_instr)
          end
          super(absolute_path)
        end

        def self.set_modules_to_instrument(modules)
          @to_instrument_modules = modules.to_set
        end
      end

      # Used to report handled exceptions
      class Component
        ERRORTRACKING_FAILURE =
          begin
            require "errortracker.#{RUBY_VERSION[/\d+.\d+/]}_#{RUBY_PLATFORM}"
            nil
          rescue LoadError => e
            e.message
          end

        def self.build(settings, agent_settings, tracer)
          new(
            tracer: tracer,
            to_instrument: settings.errortracking.to_instrument,
            to_instrument_modules: settings.errortracking.to_instrument_modules,
          ).tap(&:start)
        end

        def initialize(tracer:, to_instrument:, to_instrument_modules:)
          @tracer = tracer
          @to_instrument = to_instrument
          @to_instrument_modules = to_instrument_modules
        end

        def start
          self.class._native_start(
            tracer: @tracer,
            to_instrument: @to_instrument,
            to_instrument_modules: @to_instrument_modules
          )

          RequireHooks.set_modules_to_instrument(@to_instrument_modules)
          Kernel.prepend(RequireHooks) unless @to_instrument_modules.empty?
        end

        def stop
          self.class._native_stop
        end
      end
    end
  end
end
