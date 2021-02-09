module Datadog
  module Profiling
    module Ext
      # Monkey patches Ruby's `Thread` with our `Ext::CThread` to enable CPU-time profiling
      module CPU
        FFI_MINIMUM_VERSION = Gem::Version.new('1.0')

        def self.supported?
          unsupported_reason.nil?
        end

        def self.apply!
          return false unless supported?

          # Applying CThread to Thread will ensure any new threads
          # will provide a thread/clock ID for CPU timing.
          require 'ddtrace/profiling/ext/cthread'
          ::Thread.send(:prepend, Profiling::Ext::CThread)
        end

        def self.unsupported_reason
          # Note: Only the first matching reason is returned, so try to keep a nice order on reasons -- e.g. tell users
          # first that they can't use this on macOS before telling them that they have the wrong ffi version

          if RUBY_ENGINE == 'jruby'
            'JRuby is not supported'
          elsif RUBY_PLATFORM =~ /darwin/
            'Feature requires Linux; macOS is not supported'
          elsif RUBY_PLATFORM =~ /(mswin|mingw)/
            'Feature requires Linux; Windows is not supported'
          elsif RUBY_PLATFORM !~ /linux/
            "Feature requires Linux; #{RUBY_PLATFORM} is not supported"
          elsif Gem::Version.new(RUBY_VERSION) < Gem::Version.new('2.1')
            'Ruby >= 2.1 is required'
          elsif Gem.loaded_specs['ffi'].nil?
            "Missing ffi gem dependency; please add `gem 'ffi', '~> 1.0'` to your Gemfile or gems.rb file"
          elsif Gem.loaded_specs['ffi'].version < FFI_MINIMUM_VERSION
            'Your ffi gem dependency is too old; ensure that you have ffi >= 1.0 by ' \
            "adding `gem 'ffi', '~> 1.0'` to your Gemfile or gems.rb file"
          end
        end
      end
    end
  end
end
