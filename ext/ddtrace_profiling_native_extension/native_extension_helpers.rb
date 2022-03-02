# frozen_string_literal: true

# typed: ignore

require 'libddprof'

module Datadog
  module Profiling
    module NativeExtensionHelpers
      ENV_NO_EXTENSION = 'DD_PROFILING_NO_EXTENSION'

      # Older Rubies don't have the MJIT header, used by the JIT compiler, so we need to use a different approach
      CAN_USE_MJIT_HEADER = RUBY_VERSION >= '2.6'

      # Used to check if profiler is supported, including user-visible clear messages explaining why their
      # system may not be supported.
      # rubocop:disable Metrics/ModuleLength
      module Supported
        private_class_method def self.explain_issue(*reason, suggested:)
          { reason: reason, suggested: suggested }
        end

        def self.supported?
          unsupported_reason.nil?
        end

        def self.unsupported_reason
          disabled_via_env? ||
            on_jruby? ||
            on_truffleruby? ||
            on_windows? ||
            on_macos? ||
            on_unknown_os? ||
            not_on_amd64_or_arm64? ||
            expected_to_use_mjit_but_mjit_is_disabled? ||
            libddprof_not_usable?
        end

        # This banner will show up in the logs/terminal while compiling the native extension
        def self.failure_banner_for(reason:, suggested:)
          prettify_lines = proc { |lines| lines.map { |line| "| #{line.ljust(76)} |" }.join("\n") }
          %(
+------------------------------------------------------------------------------+
| Could not compile the Datadog Continuous Profiler because                    |
#{prettify_lines.call(reason)}
|                                                                              |
| The Datadog Continuous Profiler will not be available,                       |
| but all other ddtrace features will work fine!                               |
|                                                                              |
#{prettify_lines.call(suggested)}
+------------------------------------------------------------------------------+
          )
        end

        # This will be saved in a file to later be presented while operating the gem
        def self.render_skipped_reason_file(reason:, suggested:)
          [*reason, *suggested].join(' ')
        end

        CONTACT_SUPPORT = [
          'For help solving this issue, please contact Datadog support at',
          '<https://docs.datadoghq.com/help/>.',
        ].freeze

        REPORT_ISSUE = [
          'If you needed to use this, please tell us why on',
          '<https://github.com/DataDog/dd-trace-rb/issues/new> so we can fix it :)',
        ].freeze

        GET_IN_TOUCH = [
          "Get in touch with us if you're interested in profiling your app!"
        ].freeze

        # Validation for this check is done in extconf.rb because it relies on mkmf
        FAILED_TO_CONFIGURE_LIBDDPROF = explain_issue(
          'there was a problem in setting up the `libddprof` dependency.',
          suggested: CONTACT_SUPPORT,
        )

        # Validation for this check is done in extconf.rb because it relies on mkmf
        COMPILATION_BROKEN = explain_issue(
          'compilation of the Ruby VM just-in-time header failed.',
          'Your C compiler or Ruby VM just-in-time compiler seem to be broken.',
          suggested: CONTACT_SUPPORT,
        )

        private_class_method def self.disabled_via_env?
          disabled_via_env = explain_issue(
            'the `DD_PROFILING_NO_EXTENSION` environment variable is/was set to',
            '`true` during installation.',
            suggested: REPORT_ISSUE,
          )

          return unless ENV[ENV_NO_EXTENSION].to_s.strip.downcase == 'true'

          disabled_via_env
        end

        private_class_method def self.on_jruby?
          jruby_not_supported = explain_issue(
            'JRuby is not supported by the Datadog Continuous Profiler.',
            suggested: GET_IN_TOUCH,
          )

          jruby_not_supported if RUBY_ENGINE == 'jruby'
        end

        private_class_method def self.on_truffleruby?
          truffleruby_not_supported = explain_issue(
            'TruffleRuby is not supported by the ddtrace gem.',
            suggested: GET_IN_TOUCH,
          )

          truffleruby_not_supported if RUBY_ENGINE == 'truffleruby'
        end

        # See https://docs.datadoghq.com/tracing/setup_overview/setup/ruby/#microsoft-windows-support for current
        # state of Windows support in ddtrace.
        private_class_method def self.on_windows?
          windows_not_supported = explain_issue(
            'Microsoft Windows is not supported by the Datadog Continuous Profiler.',
            suggested: GET_IN_TOUCH,
          )

          windows_not_supported if Gem.win_platform?
        end

        private_class_method def self.on_macos?
          macos_not_supported = explain_issue(
            'macOS is currently not supported by the Datadog Continuous Profiler.',
            suggested: GET_IN_TOUCH,
          )
          # For development only; not supported otherwise
          macos_testing_override = ENV['DD_PROFILING_MACOS_TESTING'] == 'true'

          macos_not_supported if RUBY_PLATFORM.include?('darwin') && !macos_testing_override
        end

        private_class_method def self.on_unknown_os?
          unknown_os_not_supported = explain_issue(
            'your operating system is not supported by the Datadog Continuous Profiler.',
            suggested: GET_IN_TOUCH,
          )

          unknown_os_not_supported unless RUBY_PLATFORM.include?('darwin') || RUBY_PLATFORM.include?('linux')
        end

        private_class_method def self.not_on_amd64_or_arm64?
          architecture_not_supported = explain_issue(
            'your CPU architecture is not supported by the Datadog Continuous Profiler.',
            suggested: GET_IN_TOUCH,
          )

          architecture_not_supported unless RUBY_PLATFORM.start_with?('x86_64', 'aarch64')
        end

        # On some Rubies, we require the mjit header to be present. If Ruby was installed without MJIT support, we also skip
        # building the extension.
        private_class_method def self.expected_to_use_mjit_but_mjit_is_disabled?
          ruby_without_mjit = explain_issue(
            'your Ruby has been compiled without JIT support (--disable-jit-support).',
            'The profiling native extension requires a Ruby compiled with JIT support,',
            'even if the JIT is not in use by the application itself.',
            suggested: CONTACT_SUPPORT,
          )

          ruby_without_mjit if CAN_USE_MJIT_HEADER && RbConfig::CONFIG['MJIT_SUPPORT'] != 'yes'
        end

        private_class_method def self.libddprof_not_usable?
          libddprof_no_binaries = explain_issue(
            'the `libddprof` gem installed on your system is missing platform-specific',
            'binaries. Make sure you install a platform-specific version of the gem,',
            'and that you are not enabling the `force_ruby_platform` bundler option,',
            'nor the `BUNDLE_FORCE_RUBY_PLATFORM` environment variable.',
            suggested: CONTACT_SUPPORT,
          )
          return libddprof_no_binaries unless Libddprof.binaries?

          unless Libddprof.pkgconfig_folder
            explain_issue(
              'the `libddprof` gem installed on your system is missing binaries for your',
              'platform variant.',
              "(Your platform: `#{Gem::Platform.local}`)",
              "(Available binaries: `#{Libddprof.available_binaries})",
              suggested: CONTACT_SUPPORT,
            )
          end
        end
      end
      # rubocop:enable Metrics/ModuleLength
    end
  end
end
