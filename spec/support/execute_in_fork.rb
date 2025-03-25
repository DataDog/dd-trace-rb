require_relative 'platform_helpers'

module ForkableExample
  def finish(reporter)
    # TODO: better name than execute_in_fork?
    if @metadata[:execute_in_fork] && Process.ppid != 1
      super ? exit(0) : exit(1)
    else
      super
    end
  end

  EXAMPLE_SENTINEL = Module.new
  MODULE_VALUE = Struct.new(:name)

  def run(example_group_instance, reporter)
    if @metadata[:execute_in_fork]
      reader, writer = IO.pipe

      reader.binmode
      writer.binmode

      pid = fork do
        reporter.singleton_class.prepend(ForkableExample::Reporter)
        execution_result.singleton_class.prepend(ForkableExample::ExecutionResult)
        execution_result.instance_variable_set(:@fork_writer_pipe, writer)
        reporter.instance_variable_set(:@fork_writer_pipe, writer)

        reporter.instance_variable_set(:@fork_example_sentinel, self)

        reader.close

        super

        # writer.puts "Hello from child process"
        writer.close
      end

      writer.close

      _, status = Process.wait2(pid)

      while (read_size = reader.gets)
        call = Marshal.load(reader.read(Integer(read_size)))

        args = call[:args]
        args.map! do |arg|
          if arg == EXAMPLE_SENTINEL
            self
          elsif arg.is_a?(MODULE_VALUE)
            ::Object.const_get(arg.name)
          elsif arg.is_a?(RSpec::Core::Notifications::ExampleNotification) && arg.example == EXAMPLE_SENTINEL
            ::RSpec::Core::Notifications::ExampleNotification.for(self)
          else
            arg
          end
        end

        # puts("call: #{call}")

        if call[:receiver] == :reporter
          reporter.send(call[:method], *args)
        elsif call[:receiver] == :execution_result
          execution_result.send(call[:method], *args)
        end
      end

      reader.close

      status.success?
    else
      super
    end
  end

  module Reporter


      # PUBLIC_INTERNAL_METHODS = [:start, :stop, :publish, :finish, :close_after, :notify, :fail_fast_limit_met?]
     RSpec::Core::Reporter.instance_methods(false).each do |method|
      define_method(method) do |*args|
        original_args = args


        unless @fork_instrumenting # Nested calls are skipped, since they will invoked by the first call site
          begin
            @fork_instrumenting = true

            args = args.map do |arg|
              if arg == @fork_example_sentinel
                EXAMPLE_SENTINEL
              elsif arg.is_a?(Module)
                MODULE_VALUE.new(arg.name)
              elsif arg.is_a?(::RSpec::Core::Notifications::ExampleNotification) && arg.example == @fork_example_sentinel
                ::RSpec::Core::Notifications::ExampleNotification.send(:new, EXAMPLE_SENTINEL)
              else
                arg
              end
            end

          # puts({ method: method, args: args })

          dump = Marshal.dump({ receiver: :reporter, method: method, args: args })
          # Write a header hex int with the size of the next object dump
          @fork_writer_pipe.write(sprintf("0x%x\n", dump.bytesize))
          @fork_writer_pipe.write(dump)

            # puts({ method: method, args: args })
          rescue => e
            puts "ERRORERRORERROR 1111"
            puts args
            puts e
          end
        end

        super(*original_args)
      ensure
        @fork_instrumenting = false
      end
    end
  end

  module ExecutionResult
    ::RSpec::Core::Example::ExecutionResult.instance_methods(false).reject{|m|m.to_s.end_with?('?')}.each do |method|
      define_method(method) do |*args|
        original_args = args

        unless @fork_instrumenting # Nested calls are skipped, since they will invoked by the first call site
          begin
            @fork_instrumenting = true

            # args = args.map do |arg|
            #   if arg == @fork_example_sentinel
            #     EXAMPLE_SENTINEL
            #   elsif arg.is_a?(Module)
            #     MODULE_VALUE.new(arg.name)
            #   else
            #     arg
            #   end
            # end

            # puts({ method: method, args: args })

            dump = Marshal.dump({ receiver: :execution_result, method: method, args: args })
            # Write a header hex int with the size of the next object dump
            @fork_writer_pipe.write(sprintf("0x%x\n", dump.bytesize))
            @fork_writer_pipe.write(dump)

            # puts({ method: method, args: args })
          rescue => e
            puts "ERRORERRORERROR 2222"
            puts args
            puts e
          end
        end

        super(*original_args)
      ensure
        @fork_instrumenting = false
      end
    end
  end
end

RSpec::Core::Example.prepend(ForkableExample) if PlatformHelpers.supports_fork?
