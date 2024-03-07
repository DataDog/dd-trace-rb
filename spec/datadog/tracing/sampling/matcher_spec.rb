require 'spec_helper'

require 'datadog/tracing/sampling/matcher'

RSpec.describe Datadog::Tracing::Sampling::SimpleMatcher do
  let(:span_op) { Datadog::Tracing::SpanOperation.new(span_name, service: span_service, resource: span_resource) }
  let(:span_name) { 'operation.name' }
  let(:span_service) { nil }
  let(:span_resource) { nil }

  describe '#match?' do
    subject(:match?) { rule.match?(span_op) }

    context 'with a name matcher' do
      let(:rule) { described_class.new(name: name) }

      context 'with a regexp' do
        context 'matching' do
          let(:name) { /.*/ }

          it { is_expected.to eq(true) }
        end

        context 'not matching' do
          let(:name) { /^$/ }

          it { is_expected.to eq(false) }
        end
      end

      context 'with a string' do
        context 'matching' do
          let(:name) { span_name.to_s }

          it { is_expected.to eq(true) }
        end

        context 'not matching' do
          let(:name) { '' }

          it { is_expected.to eq(false) }
        end
      end

      context 'with a proc' do
        context 'matching' do
          let(:name) { ->(n) { n == span_name } }

          it { is_expected.to eq(true) }
        end

        context 'not matching' do
          let(:name) { ->(_n) { false } }

          it { is_expected.to eq(false) }
        end
      end
    end

    context 'with a service matcher' do
      let(:rule) { described_class.new(service: service) }

      context 'when span service name is present' do
        let(:span_service) { 'service-1' }

        context 'with a regexp' do
          context 'matching' do
            let(:service) { /.*/ }

            it { is_expected.to eq(true) }
          end

          context 'not matching' do
            let(:service) { /^$/ }

            it { is_expected.to eq(false) }
          end
        end

        context 'with a string' do
          context 'matching' do
            let(:service) { span_service.to_s }

            it { is_expected.to eq(true) }
          end

          context 'not matching' do
            let(:service) { '' }

            it { is_expected.to eq(false) }
          end
        end

        context 'with a proc' do
          context 'matching' do
            let(:service) { ->(n) { n == span_service } }

            it { is_expected.to eq(true) }
          end

          context 'not matching' do
            let(:service) { ->(_n) { false } }

            it { is_expected.to eq(false) }
          end
        end
      end

      context 'when span service is not present' do
        let(:service) { /.*/ }

        it { is_expected.to eq(false) }
      end
    end

    context 'with a resource matcher' do
      let(:rule) { described_class.new(resource: resource) }

      context 'when span resource name is present' do
        let(:span_resource) { 'resource-1' }

        context 'with a regexp' do
          context 'matching' do
            let(:resource) { /.*/ }

            it { is_expected.to eq(true) }
          end

          context 'not matching' do
            let(:resource) { /^$/ }

            it { is_expected.to eq(false) }
          end
        end

        context 'with a string' do
          context 'matching' do
            let(:resource) { span_resource.to_s }

            it { is_expected.to eq(true) }
          end

          context 'not matching' do
            let(:resource) { '' }

            it { is_expected.to eq(false) }
          end
        end

        context 'with a proc' do
          context 'matching' do
            let(:resource) { ->(n) { n == span_resource } }

            it { is_expected.to eq(true) }
          end

          context 'not matching' do
            let(:resource) { ->(_n) { false } }

            it { is_expected.to eq(false) }
          end
        end
      end

      context 'when span resource is not present' do
        let(:resource) { /.*/ }

        it { is_expected.to eq(false) }
      end
    end

    context 'with name and service matchers' do
      let(:rule) { described_class.new(name: name, service: service) }

      let(:name) { /.*/ }
      let(:service) { /.*/ }

      context 'when span service name is present' do
        let(:span_service) { 'service-1' }

        it { is_expected.to eq(true) }
      end

      context 'when span service is not present' do
        it { is_expected.to eq(false) }
      end
    end

    context 'with name and resource matchers' do
      let(:rule) { described_class.new(name: name, resource: resource) }

      let(:name) { /.*/ }
      let(:resource) { /.*/ }

      context 'when span resource name is present' do
        let(:span_resource) { 'resource-1' }

        it { is_expected.to eq(true) }
      end

      context 'when span resource is not present' do
        it { is_expected.to eq(false) }
      end
    end

    context 'with service and resource matchers' do
      let(:rule) { described_class.new(service: service, resource: resource) }

      let(:service) { /.*/ }
      let(:resource) { /.*/ }

      context 'when span service and resource service are present' do
        let(:span_service) { 'service-1' }
        let(:span_resource) { 'resource-1' }

        it { is_expected.to eq(true) }
      end

      context 'when span service is not present' do
        let(:span_resource) { 'resource-1' }
        it { is_expected.to eq(false) }
      end

      context 'when span resource is not present' do
        let(:span_service) { 'service-1' }
        it { is_expected.to eq(false) }
      end

      context 'when neither span service nor resource is present' do
        it { is_expected.to eq(false) }
      end
    end

    context 'with name, service, and resource matchers' do
      let(:rule) { described_class.new(name: name, service: service, resource: resource) }

      let(:name) { /.*/ }
      let(:service) { /.*/ }
      let(:resource) { /.*/ }

      context 'when span service and resource service are present' do
        let(:span_service) { 'service-1' }
        let(:span_resource) { 'resource-1' }

        it { is_expected.to eq(true) }
      end
    end
  end
end

RSpec.describe Datadog::Tracing::Sampling::ProcMatcher do
  let(:span_op) { Datadog::Tracing::SpanOperation.new(span_name, service: span_service, resource: span_resource) }
  let(:span_name) { 'operation.name' }
  let(:span_service) { nil }
  let(:span_resource) { 'resource' }

  describe '#match?' do
    subject(:match?) { rule.match?(span_op) }

    let(:rule) { described_class.new(&block) }

    context 'with matching block' do
      let(:block) do
        lambda do |name, service, resource|
          name == span_name && service == span_service && resource == span_resource
        end
      end

      it { is_expected.to eq(true) }
    end

    context 'with mismatching block' do
      let(:block) { ->(_name, _service, _resource) { false } }

      it { is_expected.to eq(false) }
    end
  end
end
