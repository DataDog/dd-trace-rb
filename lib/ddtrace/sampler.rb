require 'forwardable'

require 'ddtrace/ext/priority'

module Datadog
  # \Sampler performs client-side trace sampling.
  class Sampler
    def sample(_span)
      raise NotImplementedError, 'samplers have to implement the sample() method'
    end
  end

  # \AllSampler samples all the traces.
  class AllSampler < Sampler
    def sample(span)
      span.sampled = true
    end
  end

  # \RateSampler is based on a sample rate.
  class RateSampler < Sampler
    KNUTH_FACTOR = 1111111111111111111
    SAMPLE_RATE_METRIC_KEY = '_sample_rate'.freeze()

    attr_reader :sample_rate

    # Initialize a \RateSampler.
    # This sampler keeps a random subset of the traces. Its main purpose is to
    # reduce the instrumentation footprint.
    #
    # * +sample_rate+: the sample rate as a \Float between 0.0 and 1.0. 0.0
    #   means that no trace will be sampled; 1.0 means that all traces will be
    #   sampled.
    def initialize(sample_rate = 1.0)
      unless sample_rate > 0.0 && sample_rate <= 1.0
        Datadog::Tracer.log.error('sample rate is not between 0 and 1, disabling the sampler')
        sample_rate = 1.0
      end

      self.sample_rate = sample_rate
    end

    def sample_rate=(sample_rate)
      @sample_rate = sample_rate
      @sampling_id_threshold = sample_rate * Span::MAX_ID
    end

    def sample(span)
      span.set_metric(SAMPLE_RATE_METRIC_KEY, @sample_rate)
      span.sampled = ((span.trace_id * KNUTH_FACTOR) % Datadog::Span::MAX_ID) <= @sampling_id_threshold
    end
  end

  # \RateByServiceSampler samples different services at different rates
  class RateByServiceSampler < Sampler
    DEFAULT_KEY = 'service:,env:'.freeze

    def initialize(rate = 1.0, opts = {})
      @env = opts.fetch(:env, Datadog.tracer.tags[:env])
      @mutex = Mutex.new
      @fallback = RateSampler.new(rate)
      @sampler = { DEFAULT_KEY => @fallback }
    end

    def sample(span)
      key = key_for(span)

      @mutex.synchronize do
        @sampler.fetch(key, @fallback).sample(span)
      end
    end

    def update(rate_by_service)
      @mutex.synchronize do
        @sampler.delete_if { |key, _| key != DEFAULT_KEY && !rate_by_service.key?(key) }

        rate_by_service.each do |key, rate|
          @sampler[key] ||= RateSampler.new(rate)
          @sampler[key].sample_rate = rate
        end
      end
    end

    private

    def key_for(span)
      "service:#{span.service},env:#{@env}"
    end
  end

  # \PrioritySampler
  class PrioritySampler
    extend Forwardable

    def initialize(opts = {})
      @post_sampler = opts[:post_sampler] || RateByServiceSampler.new
    end

    def sample(span)
      # If we haven't sampled this trace yet, do so.
      # Otherwise we want to keep whatever priority has already been assigned.
      unless sampled_by_upstream(span)
        # Use the underlying sampler to "roll the dice" and see how we assign it priority.
        # This sampler derives rates from the agent, which updates the sampler's rates
        # whenever traces are submitted to the agent.
        perform_sampling(span).tap do |sampled|
          value = sampled ? Datadog::Ext::Priority::AUTO_KEEP : Datadog::Ext::Priority::AUTO_REJECT

          if span.context
            span.context.sampling_priority = value
          else
            # Set the priority directly on the span instead, since otherwise
            # it won't receive the appropriate tag.
            span.set_metric(
              Ext::DistributedTracing::SAMPLING_PRIORITY_KEY,
              value
            )
          end
        end
      end

      # Priority sampling *always* marks spans as sampled, so we flush them to the agent.
      # This will happen regardless of whether the trace is kept or ultimately rejected.
      # Otherwise metrics for traces will not be accurate, since the agent will have an
      # incomplete dataset.
      span.sampled = true
    end

    def_delegators :@post_sampler, :update

    private

    def sampled_by_upstream(span)
      span.context && !span.context.sampling_priority.nil?
    end

    def perform_sampling(span)
      @post_sampler.sample(span)
    end
  end
end
