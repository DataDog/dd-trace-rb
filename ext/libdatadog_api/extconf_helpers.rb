# frozen_string_literal: true

module Datadog
  module LibdatadogApi
    module ExtconfHelpers
      LIBDATADOG_VERSION = '~> 11.0.0.1.0'

      # TODO: Add fail install if libdatadog missing

      # Used to check if profiler is supported, including user-visible clear messages explaining why their
      # system may not be supported.
      module Supported
        private_class_method def self.explain_issue(*reason, suggested:)
          { reason: reason, suggested: suggested }
        end

        def self.supported?
          unsupported_reason.nil?
        end

        def self.unsupported_reason
          libdatadog_not_available? || libdatadog_not_usable?
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
                'but all other datadog features will work fine!',
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
          'You can also check out the Continuous Profiler troubleshooting page at',
          '<https://dtdg.co/ruby-profiler-troubleshooting>.'
        ].freeze

        GET_IN_TOUCH = [
          "Get in touch with us if you're interested in profiling your app!"
        ].freeze

        UPGRADE_RUBY = [
          'Upgrade to a modern Ruby to enable profiling for your app.'
        ].freeze

        # Validation for this check is done in extconf.rb because it relies on mkmf
        FAILED_TO_CONFIGURE_LIBDATADOG = explain_issue(
          'there was a problem in setting up the `libdatadog` dependency.',
          suggested: CONTACT_SUPPORT,
        )

        # Validation for this check is done in extconf.rb because it relies on mkmf
        COMPILATION_BROKEN = explain_issue(
          'compilation of the Ruby VM just-in-time header failed.',
          'Your C compiler or Ruby VM just-in-time compiler seem to be broken.',
          suggested: CONTACT_SUPPORT,
        )

        # Validation for this check is done in extconf.rb because it relies on mkmf
        PKG_CONFIG_IS_MISSING = explain_issue(
          # ----------------------------------------------------------------------------+
          'the `pkg-config` system tool is missing.',
          'This issue can usually be fixed by installing one of the following:',
          'the `pkg-config` package on Homebrew and Debian/Ubuntu-based Linux;',
          'the `pkgconf` package on Arch and Alpine-based Linux;',
          'the `pkgconf-pkg-config` package on Fedora/Red Hat-based Linux.',
          '(Tip: When fixing this, ensure `pkg-config` is installed **before**',
          'running `bundle install`, and remember to clear any installed gems cache).',
          suggested: CONTACT_SUPPORT,
        )

        private_class_method def self.libdatadog_not_available?
          begin
            gem 'libdatadog', LIBDATADOG_VERSION
            require 'libdatadog'
            nil
          # rubocop:disable Lint/RescueException
          rescue Exception => e
            explain_issue(
              'there was an exception during loading of the `libdatadog` gem:',
              e.class.name,
              *e.message.split("\n"),
              *Array(e.backtrace),
              '.',
              suggested: CONTACT_SUPPORT,
            )
          end
          # rubocop:enable Lint/RescueException
        end

        private_class_method def self.libdatadog_not_usable?
          no_binaries_for_current_platform = explain_issue(
            'the `libdatadog` gem installed on your system is missing binaries for your',
            'platform variant.',
            "(Your platform: `#{Libdatadog.current_platform}`)",
            '(Available binaries:',
            "`#{Libdatadog.available_binaries.join('`, `')}`)",
            suggested: CONTACT_SUPPORT,
          )

          no_binaries_for_current_platform unless Libdatadog.pkgconfig_folder
        end
      end
    end
  end
end
