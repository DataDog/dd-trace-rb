# typed: true

module Datadog
  module Profiling
    module NativeExtensionHelpers
      ENV_NO_EXTENSION = 'DD_PROFILING_NO_EXTENSION'.freeze

      # Older Rubies don't have the MJIT header, used by the JIT compiler, so we need to use a different approach
      CAN_USE_MJIT_HEADER = RUBY_VERSION >= '2.6'

      # Used to check if profiler is supported, including user-visible clear messages explaining why their
      # system may not be supported.
      module Supported
        def self.supported?
          unsupported_reason.nil?
        end

        def self.unsupported_reason
          disabled_via_env? ||
            on_jruby? ||
            on_truffleruby? ||
            on_windows? ||
            on_unknown_os? ||
            not_on_x86_64? ||
            expected_to_use_mjit_but_mjit_is_disabled? ||
            libddprof_not_usable?
        end

        private_class_method def self.skipping_build_banner(details)
          %(
+------------------------------------------------------------------------------+
| Skipping build of profiling native extension:                                |
#{details.strip}
+------------------------------------------------------------------------------+
)
        end

        private_class_method def self.disabled_via_env?
          return unless ENV[ENV_NO_EXTENSION].to_s.strip.downcase == 'true'

          skipping_build_banner %(
| `DD_PROFILING_NO_EXTENSION` environment variable is set to `true`.           |
|                                                                              |
| The Datadog Continuous Profiler will not be available,                       |
| but all other ddtrace features will work fine!                               |
|                                                                              |
| If you needed to use this, please tell us why on                             |
| <https://github.com/DataDog/dd-trace-rb/issues/new> so we can fix it :\)      |
)
        end

        private_class_method def self.on_jruby?
          return unless RUBY_ENGINE == 'jruby'

          skipping_build_banner %(
| JRuby is not supported by the Datadog Continuous Profiler.                   |
|                                                                              |
| All other ddtrace features will work fine!                                   |
|                                                                              |
| Get in touch with us if you're interested in profiling JRuby!                |
)
        end

        # We don't officially support using TruffleRuby, but we don't want to break adventurous customers either.
        private_class_method def self.on_truffleruby?
          return unless RUBY_ENGINE == 'truffleruby'

          skipping_build_banner %(
| TruffleRuby is not supported by the ddtrace gem.                             |
|                                                                              |
| Get in touch with us if you're interested in profiling TruffleRuby!          |
)
        end

        # See https://docs.datadoghq.com/tracing/setup_overview/setup/ruby/#microsoft-windows-support for current
        # state of Windows support in ddtrace.
        private_class_method def self.on_windows?
          return unless Gem.win_platform?

          skipping_build_banner %(
| Microsoft Windows is not supported by the Datadog Continuous Profiler.       |
|                                                                              |
| Get in touch with us if you're interested in profiling Ruby on Windows!      |
)
        end

        private_class_method def self.on_unknown_os?
          return if RUBY_PLATFORM.include?('darwin') || RUBY_PLATFORM.include?('linux')

          skipping_build_banner %(
| Current operating system is not supported by the Datadog Continuous Profiler.|
)
        end

        private_class_method def self.not_on_x86_64?
          return if RUBY_PLATFORM.start_with?('x86_64')

          skipping_build_banner %(
| Your CPU architecture is not supported by the Datadog Continuous Profiler.   |
|                                                                              |
| Get in touch with us if you're interested in profiling Ruby!                 |
)
        end

        # On some Rubies, we require the mjit header to be present. If Ruby was installed without MJIT support, we also skip
        # building the extension.
        private_class_method def self.expected_to_use_mjit_but_mjit_is_disabled?
          return unless CAN_USE_MJIT_HEADER && RbConfig::CONFIG['MJIT_SUPPORT'] != 'yes'

          skipping_build_banner %(
| Your Ruby has been compiled without JIT support (--disable-jit-support).     |
| The profiling native extension requires a Ruby compiled with JIT support,    |
| even if the JIT is not in use by the application itself.                     |
|                                                                              |
| The Datadog Continuous Profiler will not be available,                       |
| but all other ddtrace features will work fine!                               |
)
        end

        private_class_method def self.libddprof_not_usable?
          begin
            require 'libddprof'
          rescue LoadError
            return skipping_build_banner %(
| `libddprof` gem is not available.                                            |
|                                                                              |
| The Datadog Continuous Profiler will not be available,                       |
| but all other ddtrace features will work fine!                               |
)
          end

          unless Libddprof.binaries?
            return skipping_build_banner %(
| `libddprof` gem installed on your system is missing platform-specific        |
| binaries. Make sure you install a platform-specific version of the gem,      |
| and that you are not enabling the `force_ruby_platform` bundler option,      |
| nor the `BUNDLE_FORCE_RUBY_PLATFORM` environment variable.                   |
|                                                                              |
| The Datadog Continuous Profiler will not be available,                       |
| but all other ddtrace features will work fine!                               |
|                                                                              |
| For help solving this issue, please contact Datadog support at               |
| <https://docs.datadoghq.com/help/>.                                          |
)
          end

          unless Libddprof.pkgconfig_folder
            current_platform = Gem::Platform.local.to_s
            return skipping_build_banner %(
| `libddprof` gem installed on your system is missing binaries for your        |
| platform variant.                                                            |
| (Your platform: `#{current_platform}`)
| (Available binaries: `#{Libddprof.available_binaries})
|                                                                              |
| The Datadog Continuous Profiler will not be available,                       |
| but all other ddtrace features will work fine!                               |
|                                                                              |
| For help solving this issue, please contact Datadog support at               |
| <https://docs.datadoghq.com/help/>.                                          |
)
          end
        end
      end
    end
  end
end
