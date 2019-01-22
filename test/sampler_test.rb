
require 'helper'
require 'ddtrace/sampler'

class SamplerTest < Minitest::Test
  def setup
    Datadog::Tracer.log.level = Logger::FATAL
  end

  def teardown
    Datadog::Tracer.log.level = Logger::WARN
  end

  def test_all_sampler
    spans = [Datadog::Span.new(nil, '', trace_id: 1),
             Datadog::Span.new(nil, '', trace_id: 2),
             Datadog::Span.new(nil, '', trace_id: 3)]

    sampler = Datadog::AllSampler.new()

    spans.each do |span|
      sampler.sample(span)
      assert_equal(true, span.sampled)
    end
  end

  def test_rate_sampler_invalid
    sampler = Datadog::RateSampler.new(-1.0)
    assert_equal(1.0, sampler.sample_rate)

    sampler = Datadog::RateSampler.new(0.0)
    assert_equal(1.0, sampler.sample_rate)

    sampler = Datadog::RateSampler.new(1.5)
    assert_equal(1.0, sampler.sample_rate)
  end

  def test_rate_sampler_1_0
    spans = [Datadog::Span.new(nil, '', trace_id: 1),
             Datadog::Span.new(nil, '', trace_id: 2),
             Datadog::Span.new(nil, '', trace_id: 3)]

    sampler = Datadog::RateSampler.new(1.0)

    spans.each do |span|
      sampler.sample(span)
      assert_equal(true, span.sampled)
      assert_equal(1.0, span.get_metric(Datadog::RateSampler::SAMPLE_RATE_METRIC_KEY))
    end
  end

  def test_rate_sampler
    prng = Random.new(123)

    [0.1, 0.25, 0.5, 0.9].each do |sample_rate|
      nb_spans = 1000
      spans = Array.new(nb_spans) do
        Datadog::Span.new(nil, '', trace_id: prng.rand(Datadog::Span::MAX_ID))
      end

      sampler = Datadog::RateSampler.new(sample_rate)

      spans.each do |span|
        sampler.sample(span)

        if span.sampled
          assert_equal(sample_rate,
                       span.get_metric(Datadog::RateSampler::SAMPLE_RATE_METRIC_KEY))
        end
      end

      sampled_spans = spans.select(&:sampled)
      expected = nb_spans * sample_rate
      assert_in_delta(sampled_spans.length, expected, 0.1 * expected)
    end
  end

  def test_tracer_with_rate_sampler
    prng = Random.new(123)

    tracer = get_test_tracer()
    tracer.configure(sampler: Datadog::RateSampler.new(0.5), priority_sampling: false)

    nb_spans = 10000
    nb_spans.times do
      span = tracer.trace('test', trace_id: prng.rand(Datadog::Span::MAX_ID))
      span.finish()
    end

    spans = tracer.writer.spans
    expected = nb_spans * 0.5
    assert_in_delta(spans.length, expected, 0.1 * expected)

    spans.each do |span|
      assert_equal(0.5, span.get_metric(Datadog::RateSampler::SAMPLE_RATE_METRIC_KEY))
    end
  end

  def test_priority_sampler_handling_existing_priority
    tracer = get_test_tracer
    tracer.provider.context = Datadog::Context.new
    tracer.configure(sampler: Datadog::PrioritySampler.new)

    tracer.provider.context.sampling_priority = Datadog::Ext::Priority::USER_KEEP
    tracer.trace('test_keep', trace_id: 1) {}

    tracer.provider.context.sampling_priority = Datadog::Ext::Priority::AUTO_KEEP
    tracer.trace('test_keep', trace_id: 2) {}

    tracer.provider.context.sampling_priority = Datadog::Ext::Priority::AUTO_REJECT
    tracer.trace('test_reject', trace_id: 3) {}

    tracer.provider.context.sampling_priority = Datadog::Ext::Priority::USER_REJECT
    tracer.trace('test_reject', trace_id: 4) {}

    spans = tracer.writer.spans

    spans.each do |span|
      assert_equal('test_keep', span.name)
    end
    assert_equal(2, spans.length)
  end

  def test_priority_sampler_with_no_pre_set_priority
    tracer = get_test_tracer
    tracer.configure(sampler: Datadog::PrioritySampler.new)
    tracer.provider.context = Datadog::Context.new

    assert_nil(tracer.provider.context.sampling_priority)
    tracer.trace('test', trace_id: 1) {}

    assert_equal(1, tracer.writer.spans.length)
  end
end
