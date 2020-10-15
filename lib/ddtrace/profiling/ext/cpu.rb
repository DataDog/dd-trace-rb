module Datadog
  module Profiling
    module Ext
      # Extensions for CPU
      module CPU
        FFI_MINIMUM_VERSION = Gem::Version.new('1.0')

        def self.supported?
          RUBY_PLATFORM != 'java' \
            && Gem::Version.new(RUBY_VERSION) >= Gem::Version.new('2.1') \
            && !Gem.loaded_specs['ffi'].nil? \
            && Gem.loaded_specs['ffi'].version >= FFI_MINIMUM_VERSION
        end

        def self.apply!
          return false unless supported?

          # Applying CThread to Thread will ensure any new threads
          # will provide a thread/clock ID for CPU timing.
          require 'ddtrace/profiling/ext/cthread'
          ::Thread.send(:prepend, Profiling::Ext::CThread)
        end
      end
    end
  end
end
