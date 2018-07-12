require('helper')
require('ddtrace/sampler')
class SamplerTest < Minitest::Test
  before { Datadog::Tracer.log.level = Logger::FATAL }
  after { Datadog::Tracer.log.level = Logger::WARN }
  it('all sampler') do
    spans = [
      Datadog::Span.new(nil, '', trace_id: 1),
      Datadog::Span.new(nil, '', trace_id: 2),
      Datadog::Span.new(nil, '', trace_id: 3)
    ]
    sampler = Datadog::AllSampler.new
    spans.each do |span|
      sampler.sample(span)
      expect(span.sampled).to(eq(true))
    end
  end
  it('rate sampler invalid') do
    sampler = Datadog::RateSampler.new(-1.0)
    expect(sampler.sample_rate).to(eq(1.0))
    sampler = Datadog::RateSampler.new(0.0)
    expect(sampler.sample_rate).to(eq(1.0))
    sampler = Datadog::RateSampler.new(1.5)
    expect(sampler.sample_rate).to(eq(1.0))
  end
  it('rate sampler 1 0') do
    spans = [
      Datadog::Span.new(nil, '', trace_id: 1),
      Datadog::Span.new(nil, '', trace_id: 2),
      Datadog::Span.new(nil, '', trace_id: 3)
    ]
    sampler = Datadog::RateSampler.new(1.0)
    spans.each do |span|
      sampler.sample(span)
      expect(span.sampled).to(eq(true))
      expect(span.get_metric(Datadog::RateSampler::SAMPLE_RATE_METRIC_KEY)).to(eq(1.0))
    end
  end
  it('rate sampler') do
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
          expect(span.get_metric(Datadog::RateSampler::SAMPLE_RATE_METRIC_KEY)).to(eq(sample_rate))
        end
      end
      sampled_spans = spans.select(&:sampled)
      expected = (nb_spans * sample_rate)
      assert_in_delta(sampled_spans.length, expected, (0.1 * expected))
    end
  end
  it('tracer with rate sampler') do
    prng = Random.new(123)
    tracer = get_test_tracer
    tracer.configure(sampler: Datadog::RateSampler.new(0.5))
    nb_spans = 10000
    nb_spans.times do
      span = tracer.trace('test', trace_id: prng.rand(Datadog::Span::MAX_ID))
      span.finish
    end
    spans = tracer.writer.spans
    expected = (nb_spans * 0.5)
    assert_in_delta(spans.length, expected, (0.1 * expected))
    spans.each do |span|
      expect(span.get_metric(Datadog::RateSampler::SAMPLE_RATE_METRIC_KEY)).to(eq(0.5))
    end
  end
end
