# frozen_string_literal: true
require_relative 'errortracker'

module Datadog
  module Core
    module Errortracking
      module RequireHooks
        class << self
          attr_accessor :errortracker, :module_load_dirs, :to_instrument_modules

          def enable(errortracker)
            self.errortracker = errortracker
            self.module_load_dirs = {}
          end

          def clear
            module_load_dirs&.clear
          end
        end

        def require(path)
          self.class.to_instrument_modules.each do |mod|
            next unless path.start_with?(mod)

            gem_name = path.split('/').first

            load_dir = self.class.module_load_dirs[gem_name] || find_and_memoize_load_dir(path, gem_name)
            next unless load_dir

            rb_path = File.join(load_dir, "#{path}.rb")
            self.class.errortracker.add_instrumented_file(rb_path) if File.exist?(rb_path)
          end

          super(path)
        end

        def require_relative(path)
          caller_path = caller_locations(1, 1)[0].absolute_path
          absolute_path = File.expand_path(path, File.dirname(caller_path))

          self.class.to_instrument_modules.each do |mod|
            next unless absolute_path.match?(%r{/#{Regexp.escape(mod)}(?=/|\z)})

            self.class.errortracker.add_instrumented_file("#{absolute_path}.rb")
          end

          super(absolute_path)
        end

        private

        def find_and_memoize_load_dir(path, gem_name)
          $LOAD_PATH.each do |load_dir|
            rb_path = File.join(load_dir, "#{path}.rb")
            if File.exist?(rb_path)
              self.class.module_load_dirs[gem_name] = load_dir
              return load_dir
            end
          end
          nil
        end
      end

      # Used to report handled exceptions
      class Component
        def self.build(settings, tracer)
          return if settings.errortracking.to_instrument.empty? && settings.errortracking.to_instrument_modules.empty?
          return if !settings.errortracking.to_instrument.empty? &&
            !['all', 'user', 'third_party'].include?(settings.errortracking.to_instrument)

          new(
            tracer: tracer,
            to_instrument: settings.errortracking.to_instrument,
            to_instrument_modules: settings.errortracking.to_instrument_modules,
          ).tap(&:start)
        end

        def initialize(tracer:, to_instrument:, to_instrument_modules:)
          @to_instrument_modules = to_instrument_modules
          @errortracker = ErrorTracker.new(tracer, to_instrument, to_instrument_modules)
        end

        def start
          @errortracker.start
          unless @to_instrument_modules.empty?
            RequireHooks.enable(@errortracker)
            Kernel.prepend(RequireHooks)
          end
        end

        def stop
          @errortracker.stop
          RequireHooks.clear
        end
      end
    end
  end
end
