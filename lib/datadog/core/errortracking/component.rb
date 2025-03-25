# frozen_string_literal: true

module Datadog
  module Core
    module Errortracking
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
        end

        def stop
          self.class._native_stop
        end
      end
    end
  end
end
