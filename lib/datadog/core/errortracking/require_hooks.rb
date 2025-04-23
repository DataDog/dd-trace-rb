module Datadog
  module Core
    module Errortracking
      module RequireHooks
        @module_load_dirs = {}

        class << self
          attr_reader :module_load_dirs, :errortracker
        end

        def require(path)
          return super(path) unless RequireHooks.errortracker

          RequireHooks.errortracker.to_instrument_modules.each do |module_to_instr|
            next unless path.start_with?(module_to_instr)

            gem_name = path.split('/').first

            load_dir = RequireHooks.module_load_dirs[gem_name] || find_and_memoize_load_dir(path, gem_name)
            next unless load_dir

            rb_path = File.join(load_dir, "#{path}.rb")
            RequireHooks.errortracker.add_instrumented_file(rb_path) if File.exist?(rb_path)
          end
          super(path)
        end

        def require_relative(path)
          caller_path = caller_locations(1, 1)[0].absolute_path
          absolute_path = File.expand_path(path, File.dirname(caller_path))

          RequireHooks.errortracker.to_instrument_modules.each do |module_to_instr|
            next unless absolute_path.match?(%r{/#{Regexp.escape(module_to_instr)}(?=/|\z)})

            RequireHooks.errortracker.add_instrumented_file("#{absolute_path}.rb")
          end
          super(absolute_path)
        end

        def self.enable(errortracker)
          @errortracker = errortracker
        end

        def self.clear
          @module_load_dirs.clear
        end

        private

        def find_and_memoize_load_dir(path, gem_name)
          $LOAD_PATH.each do |load_dir|
            rb_path = File.join(load_dir, "#{path}.rb")
            if File.exist?(rb_path)
              RequireHooks.module_load_dirs[gem_name] = load_dir
              return load_dir
            end
          end
          nil
        end
      end
    end
  end
end