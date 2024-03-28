require 'datadog/tracing/sampling/span/matcher'

RSpec.describe Datadog::Tracing::Sampling::Span::Matcher do
  let(:span_op) { Datadog::Tracing::SpanOperation.new(span_name, service: span_service, resource: span_resource) }
  let(:span_name) { 'operation.name' }
  let(:span_service) { '' }
  let(:span_resource) { '' }

  describe '#match?' do
    subject(:match?) { matcher.match?(span_op) }

    {
      'plain string pattern' => [
        { pattern: 'web', input: 'web', expected: true },
        { pattern: 'web one', input: 'web one', expected: true },
        { pattern: 'web', input: 'my-web', expected: false },
      ],
      '* pattern' => [
        { pattern: 'web*', input: 'web', expected: true },
        { pattern: 'web*', input: 'web-one', expected: true },
        { pattern: 'web*', input: 'pre-web', expected: false },
        { pattern: '*web', input: 'pre-web', expected: true },
        { pattern: '*web', input: 'web-post', expected: false },
        { pattern: 'web*one', input: 'web-site-one', expected: true },
        { pattern: 'web*one', input: 'webone', expected: true },
        { pattern: 'web*site*one', input: 'web--site  one', expected: true },
        { pattern: 'web*site*one', input: 'web-nice-one', expected: false },
      ],
      '? pattern' => [
        { pattern: 'web?', input: 'web', expected: false },
        { pattern: 'web?', input: 'web1', expected: true },
        { pattern: 'web?', input: '1web', expected: false },
        { pattern: '?web', input: '1web', expected: true },
        { pattern: '?web', input: 'web1', expected: false },
        { pattern: 'web?one', input: 'web-one', expected: true },
        { pattern: 'web?one', input: 'webone', expected: false },
        { pattern: 'web?one', input: 'web-site-one', expected: false },
        { pattern: 'web?site?one', input: 'web-site-one', expected: true },
        { pattern: 'web?site?one', input: 'web-nice-one', expected: false },
      ],
      'mixed * and ? pattern' => [
        { pattern: '*web?', input: 'pre-web1', expected: true },
        { pattern: '*web?', input: 'web', expected: false },
        { pattern: '?web*', input: '1web-post', expected: true },
        { pattern: '?web*', input: 'web', expected: false },
        { pattern: 'web?one*', input: 'web-one-post', expected: true },
        { pattern: 'web?one*', input: 'webone', expected: false },
        { pattern: 'web*one?', input: 'web-one1', expected: true },
        { pattern: 'web*one?', input: 'webne1', expected: false },
        { pattern: 'web*site?one', input: 'web--site one', expected: true },
        { pattern: 'web*site?one', input: 'web--siteone', expected: false },
        { pattern: 'web?site*one', input: 'web-site  one', expected: true },
        { pattern: 'web?site*one', input: 'web-sitene', expected: false },
      ]
    }.each do |scenario, fixtures|
      context "for '#{scenario}'" do
        fixtures.each do |fixture|
          pattern = fixture[:pattern]
          input = fixture[:input]
          expected = fixture[:expected]

          context "with pattern '#{pattern}' and input '#{input}'" do
            context 'matching on span name' do
              let(:matcher) { described_class.new(name_pattern: pattern) }
              let(:span_name) { input }

              it "does #{'not ' unless expected}match" do
                is_expected.to eq(expected)
              end
            end

            context 'matching on span service' do
              let(:matcher) { described_class.new(service_pattern: pattern) }
              let(:span_service) { input }

              it "does #{'not ' unless expected}match" do
                is_expected.to eq(expected)
              end
            end

            context 'matching on span resource' do
              let(:matcher) { described_class.new(resource_pattern: pattern) }
              let(:span_resource) { input }

              it "does #{'not ' unless expected}match" do
                is_expected.to eq(expected)
              end
            end

            context 'matching on span name and service' do
              context 'with the same matching scenario for both fields' do
                let(:matcher) { described_class.new(name_pattern: pattern, service_pattern: pattern) }
                let(:span_name) { input }
                let(:span_service) { input }

                it "does #{'not ' unless expected}match" do
                  is_expected.to eq(expected)
                end
              end
            end

            context 'matching on span name and resource' do
              context 'with the same matching scenario for both fields' do
                let(:matcher) { described_class.new(name_pattern: pattern, resource_pattern: pattern) }
                let(:span_name) { input }
                let(:span_resource) { input }

                it "does #{'not ' unless expected}match" do
                  is_expected.to eq(expected)
                end
              end
            end

            context 'matching on span service and resource' do
              context 'with the same matching scenario for both fields' do
                let(:matcher) { described_class.new(service_pattern: pattern, resource_pattern: pattern) }
                let(:span_service) { input }
                let(:span_resource) { input }

                it "does #{'not ' unless expected}match" do
                  is_expected.to eq(expected)
                end
              end
            end

            context 'matching on span name, service, and resource' do
              context 'with the same matching scenario for all fields' do
                let(:matcher) do
                  described_class.new(name_pattern: pattern, service_pattern: pattern, resource_pattern: pattern)
                end
                let(:span_name) { input }
                let(:span_service) { input }
                let(:span_resource) { input }

                it "does #{'not ' unless expected}match" do
                  is_expected.to eq(expected)
                end
              end
            end
          end
        end
      end
    end

    context 'matching on span name and service' do
      let(:matcher) do
        described_class.new(
          name_pattern: name_pattern,
          service_pattern: service_pattern,
          resource_pattern: resource_pattern
        )
      end

      context 'when only name matches' do
        let(:span_name) { 'web.get' }
        let(:span_service) { 'server' }
        let(:span_resource) { 'resource' }
        let(:name_pattern) { 'web.*' }
        let(:service_pattern) { 'server2' }
        let(:resource_pattern) { 'resource2' }

        context 'does not match' do
          it { is_expected.to eq(false) }
        end
      end

      context 'when only service matches' do
        let(:span_name) { 'web.get' }
        let(:span_service) { 'server' }
        let(:span_resource) { 'resource' }
        let(:name_pattern) { 'web.post' }
        let(:service_pattern) { 'server' }
        let(:resource_pattern) { 'resource2' }

        context 'does not match' do
          it { is_expected.to eq(false) }
        end
      end

      context 'when only resource matches' do
        let(:span_name) { 'web.get' }
        let(:span_service) { 'server' }
        let(:span_resource) { 'resource' }
        let(:name_pattern) { 'web.post' }
        let(:service_pattern) { 'server2' }
        let(:resource_pattern) { 'resource' }

        context 'does not match' do
          it { is_expected.to eq(false) }
        end
      end
    end
  end
end
