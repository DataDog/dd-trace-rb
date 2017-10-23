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
      span.sampled = ((span.trace_id * KNUTH_FACTOR) % Datadog::Span::MAX_ID) <= @sampling_id_threshold
      span.set_metric(SAMPLE_RATE_METRIC_KEY, @sample_rate)
    end
  end

  # \RateByServiceSampler samples different services at different rates
  class RateByServiceSampler < Sampler
    def initialize(rate = 1.0, opts = {})
      @env = opts.fetch(:env, Datadog.tracer.tags[:env])
      @mutex = Mutex.new
      @fallback = RateSampler.new(rate)
      @sampler = {}
    end

    def sample(span)
      key = key_for(span)

      @mutex.synchronize do
        @sampler.fetch(key, @fallback).sample(span)
      end
    end

    def update(rate_by_service)
      @mutex.synchronize do
        @sampler.delete_if { |key, _| !rate_by_service.key?(key) }

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
end
