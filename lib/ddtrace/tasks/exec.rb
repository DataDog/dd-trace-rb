module Datadog
  module Tasks
    # Wraps command with Datadog tracing
    class Exec
      attr_reader :args

      def initialize(args)
        @args = args
      end

      def run
        set_rubyopt!
        exec_with_error_handling(args)
      end

      def rubyopts
        [
          '-rddtrace/profiling/preload'
        ]
      end

      private

      def set_rubyopt!
        if ENV.key?('RUBYOPT')
          ENV['RUBYOPT'] += " #{rubyopts.join(' ')}"
        else
          ENV['RUBYOPT'] = rubyopts.join(' ')
        end
      end

      # If there's an error here, rather than throwing a cryptic stack trace, let's instead have clearer messages, and
      # follow the same status codes as the shell uses
      # See also:
      # * https://www.gnu.org/software/bash/manual/html_node/Exit-Status.html
      # * https://github.com/rubygems/rubygems/blob/dd93966cac224532035deda533cba2685dfa30cc/bundler/lib/bundler/cli/exec.rb#L45
      def exec_with_error_handling(args)
        Kernel.exec(*args)
      rescue Errno::ENOENT => e
        Kernel.warn "ddtracerb exec failed: #{e.message} (command was '#{args.join(' ')}')"
        Kernel.exit 127
      rescue Errno::EACCES, Errno::ENOEXEC => e
        Kernel.warn "ddtracerb exec failed: #{e.message} (command was '#{args.join(' ')}')"
        Kernel.exit 126
      end
    end
  end
end
