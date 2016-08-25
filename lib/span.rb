
require 'json'
require 'time'



module Datadog

  class Span

    attr_accessor :name, :service, :resource,
                  :start_time, :end_time,
                  :span_id, :trace_id, :parent_id,
                  :meta, :status, :parent

    # Create a new span linked to the given tracer.
    def initialize(tracer, name, options={})
      @tracer = tracer

      @name = name
      @service = options[:service]
      @resource = options[:resource] || name

      @span_id = Datadog::next_id()
      @parent_id = options[:parent_id] || 0
      @trace_id = options[:trace_id] || @span_id

      @meta = {}
      @status = 0

      @parent = nil

      @start_time = Time.now.utc
      @end_time = nil
    end

    def trace()
      begin
        if block_given?
          yield(self)
        end
      rescue Exception => e
        self.set_error(e)
        raise
      ensure
        self.finish()
      end
    end

    def set_tag(key, value)
      return @meta[key] = value
    end

    # Return the tag wth the given key, nil if it doesn't exist.
    def get_tag(key)
      return @meta[key]
    end

    # Mark the span with the given error.
    def set_error(e)
      if e != nil
        @status = 1
        @meta["error.msg"] = e.message
        @meta["error.type"] = e.class.to_s
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

    # Set this span's parent, inheriting any properties not explicitly set.
    def set_parent(parent)
      @parent = parent
      if parent != nil
        @trace_id = parent.trace_id
        @parent_id = parent.span_id
        @service = @service || parent.service
      end
    end

    def to_hash()
      h = {
        :span_id => @span_id,
        :parent_id => @parent_id,
        :trace_id => @trace_id,
        :name => @name,
        :service => @service,
        :resource => @resource,
        :type => "FIXME",
      }

      if @start_time != nil && @end_time != nil
        h[:start] = (@start_time.to_f * 1e9).to_i
        h[:duration] = ((@end_time - @start_time) * 1e9).to_i
      end

      return h
    end

  end

  @@id_range = (0..2**64-1)

  # Return a span id.
  def self.next_id()
    return rand(@@id_range)
  end

  # Encode the given set of spans.
  def self.encode_spans(spans)
    hashes = spans.map{|s| s.to_hash()}
    return JSON.dump(hashes)
  end


end
