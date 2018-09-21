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
    PARSER = /service:([^,]*),env:(.*)$/
    MAX_POOL_SIZE = 10000

    def initialize(rate = 1.0, opts = {})
      @env = opts.fetch(:env, Datadog.tracer.tags[:env])
      @mutex = Mutex.new
      @fallback = RateSampler.new(rate)
      @sampler = {}
      @sampler_pool = []
    end

    def sample(span)
      @sampler.fetch(span.service, @fallback).sample(span)
    end

    def update(rate_by_service)
      @mutex.synchronize do
        old_fallback = @fallback
        old_sampler = @sampler

        new_fallback = @fallback
        new_sampler = {}

        rate_by_service.each do |key, rate|
          entry = parse_key(key)
          next unless entry

          env, service = entry

          if is_fallback_entry(env, service)
            new_fallback = rate_sampler(rate)
          elsif valid_entry_for_env(env, service)
            new_sampler[service] = rate_sampler(rate)
          end
        end

        @fallback = new_fallback
        @sampler = new_sampler

        # move no longer used object into the pool of bounded size
        if @sampler_pool.length < MAX_POOL_SIZE
          @sampler_pool += old_sampler.values
          @sampler_pool << old_fallback if @fallback != old_fallback
          @sampler_pool.slice!(MAX_POOL_SIZE..-1)
        end
      end
    end

    private

    def rate_sampler(rate)
      sampler = @sampler_pool.shift
      if sampler
        sampler.sampler_rate = rate
      else
        RateSampler.new(rate)
      end
    end

    def valid_entry_for_env(env, service)
      !service.empty? && env == @env.to_s
    end

    def parse_key(key)
      match = PARSER.match(key).to_a
      _, service, env = match && match.to_a

      [ env, service ] if env && service
    end

    def is_fallback_entry(env, service)
      service.empty? && env.empty?
    end
  end

  # \PrioritySampler
  class PrioritySampler
    extend Forwardable

    def initialize(opts = {})
      @base_sampler = opts[:base_sampler] || RateSampler.new
      @post_sampler = opts[:post_sampler] || RateByServiceSampler.new
    end

    def sample(span)
      return perform_sampling(span) unless span.context
      return sampled_by_upstream(span) if span.context.sampling_priority

      perform_sampling(span).tap do |sampled|
        span.context.sampling_priority = if sampled
                                           Datadog::Ext::Priority::AUTO_KEEP
                                         else
                                           Datadog::Ext::Priority::AUTO_REJECT
                                         end
      end
    end

    def_delegators :@post_sampler, :update

    private

    def sampled_by_upstream(span)
      span.sampled = priority_keep?(span.context.sampling_priority)
    end

    def priority_keep?(sampling_priority)
      sampling_priority == Datadog::Ext::Priority::USER_KEEP || sampling_priority == Datadog::Ext::Priority::AUTO_KEEP
    end

    def perform_sampling(span)
      @base_sampler.sample(span) && @post_sampler.sample(span)
    end
  end
end
