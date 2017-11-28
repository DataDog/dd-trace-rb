require 'minitest'
require 'ddtrace/sampler'

module Datadog
  class PrioritySamplerTest < Minitest::Test
    def setup
      @context = Context.new
      @span = Span.new(nil, nil, service: 'foobar', context: @context)
      @base_sampler = MiniTest::Mock.new
      @post_sampler = MiniTest::Mock.new

      @priority_sampler = PrioritySampler.new(
        base_sampler: @base_sampler,
        post_sampler: @post_sampler
      )
    end

    def test_sampling_short_circuiting
      @base_sampler.expect(:sample, false, [@span])

      refute(@priority_sampler.sample(@span))

      @base_sampler.verify
      @post_sampler.verify

      assert_equal(0, @context.sampling_priority)
    end

    def test_sampling_composition_1
      @base_sampler.expect(:sample, true, [@span])
      @post_sampler.expect(:sample, true, [@span])

      assert(@priority_sampler.sample(@span))

      @base_sampler.verify
      @post_sampler.verify

      assert(1, @context.sampling_priority)
    end

    def test_sampling_composition_2
      @base_sampler.expect(:sample, true, [@span])
      @post_sampler.expect(:sample, false, [@span])

      refute(@priority_sampler.sample(@span))

      @base_sampler.verify
      @post_sampler.verify

      assert(0, @context.sampling_priority)
    end

    def test_sampling_update
      rates_by_service = { foo: 1, bar: 0 }
      @post_sampler.expect(:update, nil, [rates_by_service])
      @priority_sampler.update(rates_by_service)
      @post_sampler.verify
    end
  end
end
