require 'spec_helper'

require 'ddtrace/ext/distributed'
require 'ddtrace/sampler'

RSpec.shared_examples 'sampler with sample rate' do |sample_rate|
  subject(:sampler_sample_rate) { sampler.sample_rate(span) }
  let(:span) { Datadog::Span.new(nil, 'dummy') }

  it { is_expected.to eq(sample_rate) }
end

RSpec.describe Datadog::AllSampler do
  subject(:sampler) { described_class.new }

  before(:each) { Datadog::Logger.log.level = Logger::FATAL }
  after(:each) { Datadog::Logger.log.level = Logger::WARN }

  describe '#sample!' do
    let(:spans) do
      [
        Datadog::Span.new(nil, '', trace_id: 1),
        Datadog::Span.new(nil, '', trace_id: 2),
        Datadog::Span.new(nil, '', trace_id: 3)
      ]
    end

    it 'samples all spans' do
      spans.each do |span|
        expect(sampler.sample!(span)).to be true
        expect(span.sampled).to be true
      end
    end
  end

  it_behaves_like 'sampler with sample rate', 1.0
end

RSpec.describe Datadog::RateSampler do
  subject(:sampler) { described_class.new(sample_rate) }

  before(:each) { Datadog::Logger.log.level = Logger::FATAL }
  after(:each) { Datadog::Logger.log.level = Logger::WARN }

  describe '#initialize' do
    context 'given a sample rate' do
      context 'that is negative' do
        let(:sample_rate) { -1.0 }
        it_behaves_like 'sampler with sample rate', 1.0 do
          let(:span) { nil }
        end
      end

      context 'that is 0' do
        let(:sample_rate) { 0.0 }
        it_behaves_like 'sampler with sample rate', 1.0
      end

      context 'that is between 0 and 1.0' do
        let(:sample_rate) { 0.5 }
        it_behaves_like 'sampler with sample rate', 0.5
      end

      context 'that is greater than 1.0' do
        let(:sample_rate) { 1.5 }
        it_behaves_like 'sampler with sample rate', 1.0
      end
    end
  end

  describe '#sample!' do
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
          sampled = sampler.sample!(span)
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
          expect(sampler.sample!(span)).to be true
          expect(span.sampled).to be true
          expect(span.get_metric(Datadog::RateSampler::SAMPLE_RATE_METRIC_KEY)).to eq(sample_rate)
        end
      end
    end
  end
end

RSpec.describe Datadog::RateByServiceSampler do
  subject(:sampler) { described_class.new }

  describe '#initialize' do
    context 'with defaults' do
      it { expect(sampler.default_key).to eq(described_class::DEFAULT_KEY) }
      it { expect(sampler.length).to eq 1 }
      it { expect(sampler.default_sampler.sample_rate).to eq 1.0 }
    end

    context 'given a default rate' do
      subject(:sampler) { described_class.new(default_rate) }
      let(:default_rate) { 0.1 }
      it { expect(sampler.default_sampler.sample_rate).to eq default_rate }
    end
  end

  describe '#resolve' do
    subject(:resolve) { sampler.resolve(span) }
    let(:span) { instance_double(Datadog::Span, service: service_name) }
    let(:service_name) { 'my-service' }

    context 'when the sampler is not configured with an :env option' do
      it { is_expected.to eq("service:#{service_name},env:") }
    end

    context 'when the sampler is configured with an :env option' do
      let(:sampler) { described_class.new(1.0, env: env) }

      context 'that is a String' do
        let(:env) { 'my-env' }
        it { is_expected.to eq("service:#{service_name},env:#{env}") }
      end

      context 'that is a Proc' do
        let(:env) { proc { 'my-env' } }
        it { is_expected.to eq("service:#{service_name},env:my-env") }
      end
    end
  end

  describe '#update' do
    subject(:update) { sampler.update(rate_by_service) }
    let(:samplers) { sampler.instance_variable_get(:@samplers) }

    include_context 'health metrics'

    context 'when new rates' do
      context 'describe a new bucket' do
        let(:new_key) { 'service:new-service,env:my-env' }
        let(:new_rate) { 0.5 }
        let(:rate_by_service) { { new_key => new_rate } }

        before { update }

        it 'adds a new sampler' do
          expect(samplers).to include(
            described_class::DEFAULT_KEY => kind_of(Datadog::RateSampler),
            new_key => kind_of(Datadog::RateSampler)
          )

          expect(samplers[new_key].sample_rate).to eq(new_rate)
        end
      end

      context 'describe an existing bucket' do
        let(:existing_key) { 'service:existing-service,env:my-env' }
        let(:new_rate) { 0.5 }
        let(:rate_by_service) { { existing_key => new_rate } }

        before do
          sampler.update(existing_key => 1.0)
          update
        end

        it 'updates the existing sampler' do
          expect(samplers).to include(
            described_class::DEFAULT_KEY => kind_of(Datadog::RateSampler),
            existing_key => kind_of(Datadog::RateSampler)
          )

          expect(samplers[existing_key].sample_rate).to eq(new_rate)

          # Expect metrics twice; one for setup, one for test.
          expect(health_metrics).to have_received(:sampling_service_cache_length).with(2).twice
        end
      end

      context 'omit an existing bucket' do
        let(:old_key) { 'service:old-service,env:my-env' }
        let(:rate_by_service) { {} }

        before do
          sampler.update(old_key => 1.0)
          update
        end

        it 'updates the existing sampler' do
          expect(samplers).to include(
            described_class::DEFAULT_KEY => kind_of(Datadog::RateSampler)
          )

          expect(samplers.keys).to_not include(old_key)
          expect(health_metrics).to have_received(:sampling_service_cache_length).with(1)
        end
      end
    end
  end
end

RSpec.describe Datadog::PrioritySampler do
  subject(:sampler) { described_class.new(base_sampler: base_sampler, post_sampler: post_sampler) }
  let(:base_sampler) { nil }
  let(:post_sampler) { nil }

  let(:sample_rate_tag_value) { nil }

  before(:each) { Datadog::Logger.log.level = Logger::FATAL }
  after(:each) { Datadog::Logger.log.level = Logger::WARN }

  describe '#sample!' do
    subject(:sample) { sampler.sample!(span) }

    shared_examples_for 'priority sampling' do
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
            expect(context.sampling_priority).to be(Datadog::Ext::Priority::AUTO_KEEP)
            expect(span.sampled).to be(true)
            expect(span.get_metric(described_class::SAMPLE_RATE_METRIC_KEY)).to eq(sample_rate_tag_value)
          end
        end

        context 'and USER_KEEP sampling priority' do
          before(:each) { context.sampling_priority = Datadog::Ext::Priority::USER_KEEP }

          it do
            expect(sample).to be true
            expect(context.sampling_priority).to be(Datadog::Ext::Priority::USER_KEEP)
            expect(span.sampled).to be(true)
            expect(span.get_metric(described_class::SAMPLE_RATE_METRIC_KEY)).to eq(sample_rate_tag_value)
          end
        end

        context 'and AUTO_KEEP sampling priority' do
          before(:each) { context.sampling_priority = Datadog::Ext::Priority::AUTO_KEEP }

          it do
            expect(sample).to be true
            expect(context.sampling_priority).to be(Datadog::Ext::Priority::AUTO_KEEP)
            expect(span.sampled).to be(true)
            expect(span.get_metric(described_class::SAMPLE_RATE_METRIC_KEY)).to eq(sample_rate_tag_value)
          end
        end

        context 'and AUTO_REJECT sampling priority' do
          before(:each) { context.sampling_priority = Datadog::Ext::Priority::AUTO_REJECT }

          it do
            expect(sample).to be true
            expect(context.sampling_priority).to be(Datadog::Ext::Priority::AUTO_REJECT)
            expect(span.sampled).to be(true) # Priority sampling always samples
            expect(span.get_metric(described_class::SAMPLE_RATE_METRIC_KEY)).to eq(sample_rate_tag_value)
          end
        end

        context 'and USER_REJECT sampling priority' do
          before(:each) { context.sampling_priority = Datadog::Ext::Priority::USER_REJECT }

          it do
            expect(sample).to be true
            expect(context.sampling_priority).to be(Datadog::Ext::Priority::USER_REJECT)
            expect(span.sampled).to be(true) # Priority sampling always samples
            expect(span.get_metric(described_class::SAMPLE_RATE_METRIC_KEY)).to eq(sample_rate_tag_value)
          end
        end
      end
    end

    shared_examples_for 'priority sampling without scaling' do
      it_behaves_like 'priority sampling' do
        # It should not set this tag; otherwise it will errantly scale up metrics.
        let(:sample_rate_tag_value) { nil }
      end
    end

    context 'when configured with defaults' do
      let(:sampler) { described_class.new }
      it_behaves_like 'priority sampling without scaling'
    end

    context 'when configured with a pre-sampler RateSampler < 1.0' do
      let(:base_sampler) { Datadog::RateSampler.new(sample_rate) }
      let(:sample_rate) { 0.5 }

      it_behaves_like 'priority sampling' do
        # It must set this tag; otherwise it won't scale up metrics properly.
        let(:sample_rate_tag_value) { sample_rate }
      end

      context 'with a priority-sampler that sets sampling rate metrics' do
        let(:post_sampler) { Datadog::RateSampler.new(1.0) }

        it_behaves_like 'priority sampling' do
          # It must set this tag; otherwise it won't scale up metrics properly.
          let(:sample_rate_tag_value) { sample_rate }
        end
      end
    end

    context 'when configured with a pre-sampler RateSampler = 1.0' do
      let(:base_sampler) { Datadog::RateSampler.new(sample_rate) }
      let(:sample_rate) { 1.0 }

      it_behaves_like 'priority sampling without scaling'

      context 'with a priority-sampler that sets sampling rate metrics' do
        let(:post_sampler) { Datadog::RateSampler.new(1.0) }

        it_behaves_like 'priority sampling without scaling'
      end
    end

    context 'when configured with a priority-sampler RateByServiceSampler < 1.0' do
      let(:post_sampler) { Datadog::RateByServiceSampler.new(sample_rate) }
      let(:sample_rate) { 0.5 }

      it_behaves_like 'priority sampling without scaling'
    end
  end
end
