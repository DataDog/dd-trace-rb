if RUBY_ENGINE == 'jruby'
  require 'logger'
  ::Logger::LogDevice.prepend(
    Module.new do
      def write(message)
        $stdout.puts("[Writing] ProcessID: #{Process.pid}, ThreadID: #{Thread.current.object_id}, Message: #{message}")
        super(message)
      end

      def close
        $stdout.puts("[Closing] ProcessID: #{Process.pid}, ThreadID: #{Thread.current.object_id}")
        super
      end
    end
  )
end
