module ForkableExample
  def finish(reporter)
    # TODO: better name than execute_in_fork?
    if @metadata[:execute_in_fork]
      super ? exit(0) : exit(1)
    else
      super
    end
  end

  def run(example_group_instance, reporter)
    if @metadata[:execute_in_fork]
      pid = fork do
        super
      end

      _, status = Process.wait2(pid)
      status.success?
    else
      super
    end
  end
end

RSpec::Core::Example.prepend(ForkableExample)
