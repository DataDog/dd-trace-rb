module Datadog
  module Profiling
    module Ext
      # Monkey patches Ruby's `Thread` with our `Ext::CThread` to enable CPU-time profiling
      module CPU
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
          ::Thread.prepend(Profiling::Ext::CThread)
          ::Thread.singleton_class.prepend(Datadog::Profiling::Ext::WrapThreadStartFork)
        end

        def self.unsupported_reason
          # NOTE: Only the first matching reason is returned, so try to keep a nice order on reasons -- e.g. tell users
          # first that they can't use this on macOS before telling them that they have the wrong ffi version

          if RUBY_ENGINE == 'jruby'
            'JRuby is not supported'
          elsif RUBY_PLATFORM.include?('darwin')
            'Feature requires Linux; macOS is not supported'
          elsif RUBY_PLATFORM =~ /(mswin|mingw)/
            'Feature requires Linux; Windows is not supported'
          elsif !RUBY_PLATFORM.include?('linux')
            "Feature requires Linux; #{RUBY_PLATFORM} is not supported"
          elsif Gem::Specification.find_all_by_name('rollbar', ROLLBAR_INCOMPATIBLE_VERSIONS).any?
            'You have an incompatible rollbar gem version installed; ensure that you have rollbar >= 3.1.2 by ' \
            "adding `gem 'rollbar', '>= 3.1.2'` to your Gemfile or gems.rb file. " \
            'See https://github.com/rollbar/rollbar-gem/pull/1018 for details'
          elsif Gem::Specification.find_all_by_name('logging').any? && logging_inherit_context_enabled?
            'The `logging` gem is installed and its thread inherit context feature is enabled. ' \
            "Please add LOGGING_INHERIT_CONTEXT=false to your application's environment variables to disable the " \
            'conflicting `logging` gem feature. ' \
            'See https://github.com/TwP/logging/pull/230 for details'
          end
        end

        private_class_method def self.logging_inherit_context_enabled?
          # The logging gem provides a mechanism to disable the conflicting behavior, see
          # https://github.com/TwP/logging/blob/ae9872d093833b2a5a34cbe1faa4e895a81f6845/lib/logging/diagnostic_context.rb#L418
          # Here we check if the behavior is enabled
          inherit_context_configuration = ENV['LOGGING_INHERIT_CONTEXT']

          inherit_context_configuration.nil? ||
          (inherit_context_configuration && !%w[false no 0].include?(inherit_context_configuration.downcase))
        end
      end
    end
  end
end
