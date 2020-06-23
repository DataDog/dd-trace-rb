module Datadog
  module Tasks
    # Prints help message for usage of `ddtrace`
    class Help
      def run
        puts %(
Usage: ddtrace [command] [arguments]
  exec [command]: Executes command with tracing & profiling preloaded.
  help:           Prints this help message.
        )
      end
    end
  end
end
