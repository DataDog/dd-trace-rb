module Datadog
  module Profiling
    module Ext
      # Monkey patches Ruby's `Thread` with our `Ext::CThread` to enable CPU-time profiling
      module CPU
        FFI_MINIMUM_VERSION = Gem::Version.new('1.0')

        # We cannot apply our CPU extension if a broken rollbar is around because that can cause customer apps to fail
        # with a SystemStackError: stack level too deep.
        #
        # This occurs whenever our extensions to Thread are applied BEFORE rollbar applies its own. This happens
        # because a loop forms: our extension tries to call Thread#initialize, but it's intercepted by rollbar, which
        # then tries to call the original Thread#initialize as well, but instead alls our extension, leading to stack
        # exhaustion.
        #
        # See https://github.com/rollbar/rollbar-gem/pull/1018 for more details on the issue
        ROLLBAR_INCOMPATIBLE_VERSIONS = Gem::Requirement.new('<= 3.1.1')

        def self.supported?
          unsupported_reason.nil?
        end

        def self.apply!
          return false unless supported?

          # Applying CThread to Thread will ensure any new threads
          # will provide a thread/clock ID for CPU timing.
          require 'ddtrace/profiling/ext/cthread'
          ::Thread.send(:prepend, Profiling::Ext::CThread)
          ::Thread.singleton_class.send(:prepend, Datadog::Profiling::Ext::WrapThreadStartFork)
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
          elsif Gem::Specification.find_all_by_name('rollbar', ROLLBAR_INCOMPATIBLE_VERSIONS).any?
            'You have an incompatible rollbar gem version installed; ensure that you have rollbar >= 3.1.2 by ' \
            "adding `gem 'rollbar', '>= 3.1.2'` to your Gemfile or gems.rb file. " \
            'See https://github.com/rollbar/rollbar-gem/pull/1018 for details.'
          end
        end
      end
    end
  end
end
