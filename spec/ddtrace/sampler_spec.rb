require 'spec_helper'

require 'ddtrace'
require 'ddtrace/sampler'

RSpec.describe Datadog::AllSampler do
  subject(:sampler) { described_class.new }

  before(:each) { Datadog::Tracer.log.level = Logger::FATAL }
  after(:each) { Datadog::Tracer.log.level = Logger::WARN }

  describe '#sample' do
    let(:spans) do
      [
        Datadog::Span.new(nil, '', trace_id: 1),
        Datadog::Span.new(nil, '', trace_id: 2),
        Datadog::Span.new(nil, '', trace_id: 3)
      ]
    end

    it 'samples all spans' do
      spans.each do |span|
        expect(sampler.sample(span)).to be true
        expect(span.sampled).to be true
      end
    end
  end
end

RSpec.describe Datadog::RateSampler do
  subject(:sampler) { described_class.new(sample_rate) }

  before(:each) { Datadog::Tracer.log.level = Logger::FATAL }
  after(:each) { Datadog::Tracer.log.level = Logger::WARN }

  describe '#initialize' do
    context 'given a sample rate' do
      context 'that is negative' do
        let(:sample_rate) { -1.0 }
        it { expect(sampler.sample_rate).to eq(1.0) }
      end

      context 'that is 0' do
        let(:sample_rate) { 0.0 }
        it { expect(sampler.sample_rate).to eq(1.0) }
      end

      context 'that is between 0 and 1.0' do
        let(:sample_rate) { 0.5 }
        it { expect(sampler.sample_rate).to eq(0.5) }
      end

      context 'that is greater than 1.0' do
        let(:sample_rate) { 1.5 }
        it { expect(sampler.sample_rate).to eq(1.0) }
      end
    end
  end

  describe '#sample' do
    let(:spans) do
      [
        Datadog::Span.new(nil, '', trace_id: 1),
        Datadog::Span.new(nil, '', trace_id: 2),
        Datadog::Span.new(nil, '', trace_id: 3)
      ]
    end

    shared_examples_for 'rate sampling' do
      let(:span_count) { 1000 }
      let(:rng) { Random.new(123) }

      let(:spans) { Array.new(span_count) { Datadog::Span.new(nil, '', trace_id: rng.rand(Datadog::Span::MAX_ID)) } }
      let(:expected_num_of_sampled_spans) { span_count * sample_rate }

      it 'samples an appropriate proportion of spans' do
        spans.each do |span|
          sampled = sampler.sample(span)
          expect(span.get_metric(Datadog::RateSampler::SAMPLE_RATE_METRIC_KEY)).to eq(sample_rate) if sampled
        end

        expect(spans.select(&:sampled).length).to be_within(expected_num_of_sampled_spans * 0.1)
          .of(expected_num_of_sampled_spans)
      end
    end

    it_behaves_like('rate sampling') { let(:sample_rate) { 0.1 } }
    it_behaves_like('rate sampling') { let(:sample_rate) { 0.25 } }
    it_behaves_like('rate sampling') { let(:sample_rate) { 0.5 } }
    it_behaves_like('rate sampling') { let(:sample_rate) { 0.9 } }

    context 'when a sample rate of 1.0 is set' do
      let(:sample_rate) { 1.0 }

      it 'samples all spans' do
        spans.each do |span|
          expect(sampler.sample(span)).to be true
          expect(span.sampled).to be true
          expect(span.get_metric(Datadog::RateSampler::SAMPLE_RATE_METRIC_KEY)).to eq(sample_rate)
        end
      end
    end
  end
end

RSpec.describe Datadog::PrioritySampler do
  subject(:sampler) { described_class.new(options) }
  let(:options) { {} }

  before(:each) { Datadog::Tracer.log.level = Logger::FATAL }
  after(:each) { Datadog::Tracer.log.level = Logger::WARN }

  describe '#sample' do
    subject(:sample) { sampler.sample(span) }

    context 'given a span without a context' do
      let(:span) { Datadog::Span.new(nil, '', trace_id: 1) }

      it do
        expect(sample).to be true
        expect(span.sampled).to be(true)
      end
    end

    context 'given a span with a context' do
      let(:span) { Datadog::Span.new(nil, '', trace_id: 1, context: context) }
      let(:context) { Datadog::Context.new }

      context 'but no sampling priority' do
        it do
          expect(sample).to be true
          expect(span.sampled).to be(true)
        end
      end

      context 'and USER_KEEP sampling priority' do
        before(:each) { context.sampling_priority = Datadog::Ext::Priority::USER_KEEP }

        it do
          expect(sample).to be true
          expect(context.sampling_priority).to be(Datadog::Ext::Priority::USER_KEEP)
          expect(span.sampled).to be(true)
        end
      end

      context 'and AUTO_KEEP sampling priority' do
        before(:each) { context.sampling_priority = Datadog::Ext::Priority::AUTO_KEEP }

        it do
          expect(sample).to be true
          expect(context.sampling_priority).to be(Datadog::Ext::Priority::AUTO_KEEP)
          expect(span.sampled).to be(true)
        end
      end

      context 'and AUTO_REJECT sampling priority' do
        before(:each) { context.sampling_priority = Datadog::Ext::Priority::AUTO_REJECT }

        it do
          expect(sample).to be true
          expect(context.sampling_priority).to be(Datadog::Ext::Priority::AUTO_REJECT)
          expect(span.sampled).to be(true) # Priority sampling always samples
        end
      end

      context 'and USER_REJECT sampling priority' do
        before(:each) { context.sampling_priority = Datadog::Ext::Priority::USER_REJECT }

        it do
          expect(sample).to be true
          expect(context.sampling_priority).to be(Datadog::Ext::Priority::USER_REJECT)
          expect(span.sampled).to be(true) # Priority sampling always samples
        end
      end
    end
  end
end
