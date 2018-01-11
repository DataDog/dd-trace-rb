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
      @base_sampler = opts[:base_sampler] || RateSampler.new
      @post_sampler = opts[:post_sampler] || RateByServiceSampler.new
    end

    def sample(span)
      span.context.sampling_priority = Datadog::Ext::Priority::AUTO_REJECT if span.context
      return unless @base_sampler.sample(span)
      return unless @post_sampler.sample(span)
      span.context.sampling_priority = Datadog::Ext::Priority::AUTO_KEEP if span.context

      true
    end

    def_delegators :@post_sampler, :update
  end
end
