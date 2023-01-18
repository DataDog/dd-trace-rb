# frozen_string_literal: true

module Datadog
  module Tracing
    module Contrib
      module Rails
        MAX_TAG_VALUE_SIZE = 4096
        private_constant :MAX_TAG_VALUE_SIZE

        # Instruments the `bin/rails runner` command.
        # This command executes the provided code with the host Rails application loaded.
        # The command can be either:
        # * `-`: for code provided through the STDIN.
        # * File path: for code provided through a local file.
        # * `inline code`: for code provided directly as a command line argument.
        # @see https://guides.rubyonrails.org/v6.1/command_line.html#bin-rails-runner
        module Runner
          def runner(code_or_file = nil, *_command_argv)
            if code_or_file == '-'
              name = Ext::SPAN_RUNNER_STDIN
              resource = nil
              operation = Ext::TAG_OPERATION_STDIN
            elsif File.exist?(code_or_file)
              name = Ext::SPAN_RUNNER_FILE
              resource = code_or_file
              operation = Ext::TAG_OPERATION_FILE
              @dd_source = File.read(code_or_file)
            else
              name = Ext::SPAN_RUNNER_INLINE
              resource = nil
              operation = Ext::TAG_OPERATION_INLINE
              @dd_source = code_or_file
            end

            Tracing.trace(
              name,
              service: Datadog.configuration.tracing[:rails][:runner_service_name],
              resource: resource,
              tags: {
                Tracing::Metadata::Ext::TAG_COMPONENT => Ext::TAG_COMPONENT,
                Tracing::Metadata::Ext::TAG_OPERATION => operation,
              }
            ) do |span|
              if @dd_source
                span.set_tag(
                  Ext::TAG_RUNNER_SOURCE,
                  Datadog::Core::Utils.truncate(@dd_source, MAX_TAG_VALUE_SIZE)
                )
              end
              Contrib::Analytics.set_rate!(span, Datadog.configuration.tracing[:rails])

              super
            end
          end

          # Capture executed source code when provided from STDIN.
          def eval(*args)
            unless @dd_source
              Datadog::Tracing.active_span.set_tag(
                Ext::TAG_RUNNER_SOURCE,
                Datadog::Core::Utils.truncate(args[0], MAX_TAG_VALUE_SIZE)
              )
            end

            super
          end

          ruby2_keywords :eval if respond_to?(:ruby2_keywords, true)
        end

        # The instrumentation target, {Rails::Command::RunnerCommand} is only loaded
        # right before `bin/rails runner` is executed. This means there's not much
        # opportunity to patch it ahead of time.
        # To ensure we can patch it successfully, we patch it's caller, {Rails::Command}
        # and promptly patch {Rails::Command::RunnerCommand} when it is loaded.
        module Command
          def find_by_namespace(*args)
            ret = super
            if defined?(::Rails::Command::RunnerCommand) && !(::Rails::Command::RunnerCommand < Runner)
              ::Rails::Command::RunnerCommand.prepend(Runner)
            end
            ret
          end

          ruby2_keywords :find_by_namespace if respond_to?(:ruby2_keywords, true)
        end
      end
    end
  end
end
