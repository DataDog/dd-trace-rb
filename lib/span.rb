require 'time'
require 'ext/errors'
require 'ext/errors'
require 'ext/errors'
require 'ext/errors'


module Datadog

  class Span

    attr_accessor :name, :start_time, :end_time,
                  :span_id, :trace_id, :parent_id,
                  :meta, :error

    def initialize(tracer, name, options={})
      @tracer = tracer
      @name = name

      @span_id = Datadog::next_id()
      @parent_id = options[:parent_id] || 0
      @trace_id = options[:trace_id] || @span_id

      @meta = {}
      @error = 0

      @start_time = Time.now.utc
      @end_time = nil
    end

    def trace()
      begin
        yield(self)
      rescue Exception => e
        self.set_error(e)
        raise e
      ensure
        return self.finish()
      end
    end

    def set_error(e)
      if e != nil
        @error = 1
        @meta["error.msg"] = e.to_s
        @meta["error.type"] = e.class
        @meta["error.stack"] = e.backtrace.join("\n")
      end
    end

    # Mark the span finished at the current time and submit it.
    def finish()
      return self.finish_at(Time.now.utc)
    end

    # Mark the span finished at the given time and submit it.
    def finish_at(end_time)
      @end_time = end_time

      if !@tracer.nil?
        @tracer.record(self)
      end

      return self
    end

    # Return a string representation of the span.
    def to_s()
      return "Span(name:#{@name},sid:#{@span_id},tid:#{@trace_id},pid:#{@parent_id})"
    end

  end

  @@id_range = (0..2**64-1)

  def self.next_id()
    return rand(@@id_range)
  end

end
