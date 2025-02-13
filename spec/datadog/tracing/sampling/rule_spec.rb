require 'spec_helper'

require 'datadog/core'
require 'datadog/tracing/sampling/matcher'
require 'datadog/tracing/sampling/rule'
require 'datadog/tracing/trace_operation'

RSpec.describe Datadog::Tracing::Sampling::Rule do
  let(:trace_op) do
    Datadog::Tracing::TraceOperation.new(
      name: trace_name,
      service: trace_service,
      resource: trace_resource,
      tags: trace_tags
    )
  end
  let(:trace_name) { 'operation.name' }
  let(:trace_service) { 'test-service' }
  let(:trace_resource) { 'test-resource' }
  let(:trace_tags) { {} }

  let(:rule) { described_class.new(matcher, sampler, provenance) }
  let(:matcher) { instance_double(Datadog::Tracing::Sampling::Matcher) }
  let(:sampler) { instance_double(Datadog::Tracing::Sampling::Sampler) }
  let(:provenance) { double('provenance') }

  describe '#match?' do
    subject(:match) { rule.match?(trace_op) }

    let(:matched) { true }

    before do
      allow(matcher).to receive(:match?).with(trace_op).and_return(matched)
    end

    context 'with matching span operation' do
      let(:matched) { true }

      it { is_expected.to eq(true) }
    end

    context 'with span operation not matching' do
      let(:matched) { false }

      it { is_expected.to eq(false) }
    end

    context 'when matcher errs' do
      let(:error) { StandardError }

      before do
        allow(matcher).to receive(:match?).and_raise(error)

        expect(Datadog.logger).to receive(:error)
          .with(a_string_including("Matcher failed. Cause: #{error}"))
        expect(Datadog::Core::Telemetry::Logger).to receive(:report)
          .with(error, description: 'Matcher failed')
      end

      it { is_expected.to be nil }
    end
  end

  describe '#sample_rate' do
    subject(:sample_rate) { rule.sample_rate(trace_op) }

    let(:sample_rate_value) { double }

    before do
      allow(sampler).to receive(:sample_rate).with(trace_op).and_return(sample_rate_value)
    end

    it { is_expected.to be(sample_rate_value) }
  end
end

RSpec.describe Datadog::Tracing::Sampling::SimpleRule do
  let(:trace_op) do
    Datadog::Tracing::TraceOperation.new(
      name: trace_name,
      service: trace_service,
      resource: trace_resource,
      tags: trace_tags
    )
  end
  let(:trace_name) { 'operation.name' }
  let(:trace_service) { 'test-service' }
  let(:trace_resource) { 'test-resource' }
  let(:trace_tags) { {} }

  describe '#initialize' do
    context 'with parameters' do
      subject(:rule) do
        described_class.new(name: name, service: service, resource: resource, sample_rate: sample_rate, tags: tags)
      end

      let(:name) { 'name' }
      let(:service) { 'service' }
      let(:resource) { 'resource' }
      let(:tags) { { 'tag key' => 'tag value' } }
      let(:sample_rate) { 0.123 }

      it 'initializes with the correct values' do
        expect(rule.matcher.name).to eq(/\Aname\z/i)
        expect(rule.matcher.service).to eq(/\Aservice\z/i)
        expect(rule.matcher.resource).to eq(/\Aresource\z/i)
        expect(rule.matcher.tags).to eq('tag key' => /\Atag\ value\z/i)
        expect(rule.sampler.sample_rate).to eq(0.123)
      end
    end

    context 'with default values' do
      subject(:rule) { described_class.new }

      it 'initializes with the correct values' do
        expect(rule.matcher.name).to eq(Datadog::Tracing::Sampling::Matcher::MATCH_ALL)
        expect(rule.matcher.service).to eq(Datadog::Tracing::Sampling::Matcher::MATCH_ALL)
        expect(rule.matcher.resource).to eq(Datadog::Tracing::Sampling::Matcher::MATCH_ALL)
        expect(rule.matcher.tags).to eq({})
        expect(rule.sampler.sample_rate).to eq(1.0)
      end
    end
  end
end
