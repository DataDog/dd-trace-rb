# frozen_string_literal: true

# typed: ignore

require 'libddprof'
require 'pathname'

module Datadog
  module Profiling
    # Helpers for extconf.rb
    module NativeExtensionHelpers
      # Can be set when customers want to skip compiling the native extension entirely
      ENV_NO_EXTENSION = 'DD_PROFILING_NO_EXTENSION'
      # Can be set to force rubygems to fail gem installation when profiling extension could not be built
      ENV_FAIL_INSTALL_IF_MISSING_EXTENSION = 'DD_PROFILING_FAIL_INSTALL_IF_MISSING_EXTENSION'

      # Older Rubies don't have the MJIT header, used by the JIT compiler, so we need to use a different approach
      CAN_USE_MJIT_HEADER = RUBY_VERSION >= '2.6'

      def self.fail_install_if_missing_extension?
        ENV[ENV_FAIL_INSTALL_IF_MISSING_EXTENSION].to_s.strip.downcase == 'true'
      end

      # Used as an workaround for a limitation with how dynamic linking works in environments where ddtrace and
      # libddprof are moved after the extension gets compiled.
      #
      # Because the libddpprof native library is installed on a non-standard system path, in order for it to be
      # found by the system dynamic linker (e.g. what takes care of dlopen(), which is used to load the profiling
      # native extension), we need to add a "runpath" -- a list of folders to search for libddprof.
      #
      # This runpath gets hardcoded at native library linking time. You can look at it using the `readelf` tool in
      # Linux: e.g. `readelf -d ddtrace_profiling_native_extension.2.7.3_x86_64-linux.so`.
      #
      # In ddtrace 1.1.0, we only set as runpath an absolute path to libddprof. (This gets set automatically by the call
      # to `pkg_config('ddprof_ffi_with_rpath')` in `extconf.rb`). This worked fine as long as libddprof was **NOT**
      # moved from the folder it was present at ddtrace installation/linking time.
      #
      # Unfortunately, environments such as Heroku and AWS Elastic Beanstalk move gems around in the filesystem after
      # installation. Thus, the profiling native extension could not be loaded in these environments
      # (see https://github.com/DataDog/dd-trace-rb/issues/2067) because libddprof could not be found.
      #
      # To workaround this issue, this method computes the **relative** path between the folder where the profiling
      # native extension is going to be installed and the folder where libddprof is installed, and returns it
      # to be set as an additional runpath. (Yes, you can set multiple runpath folders to be searched).
      #
      # This way, if both gems are moved together (and it turns out that they are in these environments),
      # the relative path can still be traversed to find libddprof.
      #
      # This is incredibly awful, and it's kinda bizarre how it's not possible to just find these paths at runtime
      # and set them correctly; rather than needing the set stuff at linking-time and then praying to $deity that
      # weird moves don't happen.
      #
      # As a curiosity, `LD_LIBRARY_PATH` can be used to influence the folders that get searched but **CANNOT BE
      # SET DYNAMICALLY**, e.g. it needs to be set at the start of the process (Ruby VM) and thus it's not something
      # we could setup when doing a `require`.
      #
      def self.libddprof_folder_relative_to_native_lib_folder(
        current_folder: __dir__,
        libddprof_pkgconfig_folder: Libddprof.pkgconfig_folder
      )
        return unless libddprof_pkgconfig_folder

        profiling_native_lib_folder = "#{current_folder}/../../lib/"
        libddprof_lib_folder = "#{libddprof_pkgconfig_folder}/../"

        Pathname.new(libddprof_lib_folder).relative_path_from(profiling_native_lib_folder).to_s
      end

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
        def self.failure_banner_for(reason:, suggested:, fail_install:)
          prettify_lines = proc { |lines| Array(lines).map { |line| "| #{line.ljust(76)} |" }.join("\n") }
          outcome =
            if fail_install
              [
                'Failing installation immediately because the ',
                "`#{ENV_FAIL_INSTALL_IF_MISSING_EXTENSION}` environment variable is set",
                'to `true`.',
                'When contacting support, please include the <mkmf.log> file that is shown ',
                'below.',
              ]
            else
              [
                'The Datadog Continuous Profiler will not be available,',
                'but all other ddtrace features will work fine!',
              ]
            end

          %(
+------------------------------------------------------------------------------+
| Could not compile the Datadog Continuous Profiler because                    |
#{prettify_lines.call(reason)}
|                                                                              |
#{prettify_lines.call(outcome)}
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
          no_binaries_for_current_platform = explain_issue(
            'the `libddprof` gem installed on your system is missing binaries for your',
            'platform variant.',
            "(Your platform: `#{Gem::Platform.local}`)",
            '(Available binaries: ',
            "`#{Libddprof.available_binaries.join('`, `')}`)",
            suggested: CONTACT_SUPPORT,
          )

          no_binaries_for_current_platform unless Libddprof.pkgconfig_folder
        end
      end
      # rubocop:enable Metrics/ModuleLength
    end
  end
end
