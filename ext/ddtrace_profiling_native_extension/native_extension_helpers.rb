# typed: ignore

module Datadog
  module Profiling
    module NativeExtensionHelpers
      ENV_NO_EXTENSION = 'DD_PROFILING_NO_EXTENSION'.freeze

      # Older Rubies don't have the MJIT header, used by the JIT compiler, so we need to use a different approach
      CAN_USE_MJIT_HEADER = RUBY_VERSION >= '2.6'

      # Used to check if profiler is supported, including user-visible clear messages explaining why their
      # system may not be supported.
      # rubocop:disable Metrics/ModuleLength
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
            not_on_amd64_or_arm64? ||
            expected_to_use_mjit_but_mjit_is_disabled? ||
            libddprof_not_usable?
        end

        private_class_method def self.disabled_via_env?
          return unless ENV[ENV_NO_EXTENSION].to_s.strip.downcase == 'true'

          DISABLED_VIA_ENV
        end

        private_class_method def self.on_jruby?
          JRUBY_NOT_SUPPORTED if RUBY_ENGINE == 'jruby'
        end

        private_class_method def self.on_truffleruby?
          TRUFFLERUBY_NOT_SUPPORTED if RUBY_ENGINE == 'truffleruby'
        end

        # See https://docs.datadoghq.com/tracing/setup_overview/setup/ruby/#microsoft-windows-support for current
        # state of Windows support in ddtrace.
        private_class_method def self.on_windows?
          WINDOWS_NOT_SUPPORTED if Gem.win_platform?
        end

        private_class_method def self.on_unknown_os?
          UNKNOWN_OS_NOT_SUPPORTED unless RUBY_PLATFORM.include?('darwin') || RUBY_PLATFORM.include?('linux')
        end

        private_class_method def self.not_on_amd64_or_arm64?
          ARCHITECTURE_NOT_SUPPORTED unless (RUBY_PLATFORM.start_with?('x86_64') || RUBY_PLATFORM.start_with?('aarch64'))
        end

        # On some Rubies, we require the mjit header to be present. If Ruby was installed without MJIT support, we also skip
        # building the extension.
        private_class_method def self.expected_to_use_mjit_but_mjit_is_disabled?
          RUBY_WITHOUT_MJIT if CAN_USE_MJIT_HEADER && RbConfig::CONFIG['MJIT_SUPPORT'] != 'yes'
        end

        private_class_method def self.libddprof_not_usable?
          begin
            require 'libddprof'
          rescue LoadError
            return LIBDDPROF_NOT_AVAILABLE
          end

          return LIBDDPROF_NO_BINARIES unless Libddprof.binaries?

          unless Libddprof.pkgconfig_folder
            current_platform = Gem::Platform.local.to_s
            %(
+------------------------------------------------------------------------------+
| Skipping build of profiling native extension:                                |
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
+------------------------------------------------------------------------------+
)
          end
        end

        DISABLED_VIA_ENV = %(
+------------------------------------------------------------------------------+
| Skipping build of profiling native extension:                                |
| `DD_PROFILING_NO_EXTENSION` environment variable is set to `true`.           |
|                                                                              |
| The Datadog Continuous Profiler will not be available,                       |
| but all other ddtrace features will work fine!                               |
|                                                                              |
| If you needed to use this, please tell us why on                             |
| <https://github.com/DataDog/dd-trace-rb/issues/new> so we can fix it :\)      |
+------------------------------------------------------------------------------+
).freeze

        JRUBY_NOT_SUPPORTED = %(
+------------------------------------------------------------------------------+
| Skipping build of profiling native extension:                                |
| JRuby is not supported by the Datadog Continuous Profiler.                   |
|                                                                              |
| All other ddtrace features will work fine!                                   |
|                                                                              |
| Get in touch with us if you're interested in profiling JRuby!                |
+------------------------------------------------------------------------------+
 ).freeze

        TRUFFLERUBY_NOT_SUPPORTED = %(
+------------------------------------------------------------------------------+
| Skipping build of profiling native extension:                                |
| TruffleRuby is not supported by the ddtrace gem.                             |
|                                                                              |
| Get in touch with us if you're interested in profiling TruffleRuby!          |
+------------------------------------------------------------------------------+
).freeze

        WINDOWS_NOT_SUPPORTED = %(
+------------------------------------------------------------------------------+
| Skipping build of profiling native extension:                                |
| Microsoft Windows is not supported by the Datadog Continuous Profiler.       |
|                                                                              |
| Get in touch with us if you're interested in profiling Ruby on Windows!      |
+------------------------------------------------------------------------------+
).freeze

        UNKNOWN_OS_NOT_SUPPORTED = %(
+------------------------------------------------------------------------------+
| Skipping build of profiling native extension:                                |
| Current operating system is not supported by the Datadog Continuous Profiler.|
+------------------------------------------------------------------------------+
).freeze

        ARCHITECTURE_NOT_SUPPORTED = %(
+------------------------------------------------------------------------------+
| Skipping build of profiling native extension:                                |
| Your CPU architecture is not supported by the Datadog Continuous Profiler.   |
|                                                                              |
| Get in touch with us if you're interested in profiling Ruby!                 |
+------------------------------------------------------------------------------+
).freeze

        RUBY_WITHOUT_MJIT = %(
+------------------------------------------------------------------------------+
| Skipping build of profiling native extension:                                |
| Your Ruby has been compiled without JIT support (--disable-jit-support).     |
| The profiling native extension requires a Ruby compiled with JIT support,    |
| even if the JIT is not in use by the application itself.                     |
|                                                                              |
| The Datadog Continuous Profiler will not be available,                       |
| but all other ddtrace features will work fine!                               |
+------------------------------------------------------------------------------+
).freeze

        LIBDDPROF_NOT_AVAILABLE = %(
+------------------------------------------------------------------------------+
| Skipping build of profiling native extension:                                |
| `libddprof` gem is not available.                                            |
|                                                                              |
| The Datadog Continuous Profiler will not be available,                       |
| but all other ddtrace features will work fine!                               |
+------------------------------------------------------------------------------+
).freeze

        LIBDDPROF_NO_BINARIES = %(
+------------------------------------------------------------------------------+
| Skipping build of profiling native extension:                                |
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
+------------------------------------------------------------------------------+
).freeze
      end
      # rubocop:enable Metrics/ModuleLength
    end
  end
end
