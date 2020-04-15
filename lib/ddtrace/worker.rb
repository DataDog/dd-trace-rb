module Datadog
  # Base class for work tasks
  class Worker
    attr_reader \
      :task

    def initialize(&block)
      @task = block
    end

    def perform(*args)
      task.call(*args) unless task.nil?
    end

    protected

    attr_writer \
      :task
  end
end
