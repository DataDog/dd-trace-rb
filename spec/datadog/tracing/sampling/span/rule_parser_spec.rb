require 'datadog/tracing/sampling/span/rule_parser'

RSpec.describe Datadog::Tracing::Sampling::Span::RuleParser do
  describe '.parse_json' do
    subject(:parse) { described_class.parse_json(rules_string) }
    let(:rules_string) { JSON.dump(json_input) }
    let(:json_input) { [] }

    shared_examples 'does not modify span' do
      it { expect { sample! }.to_not(change { span_op.send(:build_span).to_hash }) }
    end

    context 'with nil' do
      let(:rules_string) { nil }

      it 'returns nil' do
        is_expected.to be(nil)
      end
    end

    context 'invalid JSON' do
      let(:rules_string) { '-not-json-' }

      it 'warns and returns nil' do
        expect(Datadog.logger).to receive(:warn).with(include(rules_string))
        is_expected.to be(nil)
      end
    end

    context 'valid JSON' do
      context 'not a list' do
        let(:json_input) { { 'not' => 'list' } }

        it 'warns and returns nil' do
          expect(Datadog.logger).to receive(:warn).with(include(json_input.inspect))
          is_expected.to be(nil)
        end
      end

      context 'a list' do
        context 'without valid rules' do
          let(:json_input) { ['not a hash'] }

          it 'warns and returns nil' do
            expect(Datadog.logger).to receive(:warn).with(include('not a hash'))
            is_expected.to be(nil)
          end
        end

        context 'with valid rules' do
          let(:json_input) { [rule] }

          let(:rule) do
            {
              name: name,
              service: service,
              resource: resource,
              sample_rate: sample_rate,
              max_per_second: max_per_second,
            }
          end

          let(:name) { nil }
          let(:service) { nil }
          let(:resource) { nil }
          let(:sample_rate) { nil }
          let(:max_per_second) { nil }

          context 'and default values' do
            it 'delegates defaults to the rule and matcher' do
              is_expected.to contain_exactly(
                Datadog::Tracing::Sampling::Span::Rule.new(Datadog::Tracing::Sampling::Span::Matcher.new)
              )
            end
          end

          context 'with name' do
            let(:name) { 'name' }

            it 'sets the rule matcher name' do
              is_expected.to contain_exactly(
                Datadog::Tracing::Sampling::Span::Rule.new(
                  Datadog::Tracing::Sampling::Span::Matcher.new(name_pattern: name)
                )
              )
            end

            context 'with an invalid value' do
              let(:name) { { 'bad' => 'name' } }

              it 'warns and returns nil' do
                expect(Datadog.logger).to receive(:warn).with(include(name.inspect) & include('Error'))
                is_expected.to be_nil
              end
            end
          end

          context 'with service' do
            let(:service) { 'service' }

            it 'sets the rule matcher service' do
              is_expected.to contain_exactly(
                Datadog::Tracing::Sampling::Span::Rule.new(
                  Datadog::Tracing::Sampling::Span::Matcher.new(service_pattern: service)
                )
              )
            end

            context 'with an invalid value' do
              let(:service) { { 'bad' => 'service' } }

              it 'warns and returns nil' do
                expect(Datadog.logger).to receive(:warn).with(include(service.inspect) & include('Error'))
                is_expected.to be_nil
              end
            end
          end

          context 'with resource' do
            let(:resource) { 'resource' }

            it 'sets the rule matcher resource' do
              is_expected.to contain_exactly(
                Datadog::Tracing::Sampling::Span::Rule.new(
                  Datadog::Tracing::Sampling::Span::Matcher.new(resource_pattern: resource)
                )
              )
            end

            context 'with an invalid value' do
              let(:resource) { { 'bad' => 'resource' } }

              it 'warns and returns nil' do
                expect(Datadog.logger).to receive(:warn).with(include(resource.inspect) & include('Error'))
                is_expected.to be_nil
              end
            end
          end

          context 'with sample_rate' do
            let(:sample_rate) { 1.0 }

            it 'sets the rule matcher service' do
              is_expected.to contain_exactly(
                Datadog::Tracing::Sampling::Span::Rule.new(
                  Datadog::Tracing::Sampling::Span::Matcher.new, sample_rate: sample_rate
                )
              )
            end

            context 'with an invalid value' do
              let(:sample_rate) { { 'bad' => 'sample_rate' } }

              it 'warns and returns nil' do
                expect(Datadog.logger).to receive(:warn).with(include(sample_rate.inspect) & include('Error'))
                is_expected.to be_nil
              end
            end
          end

          context 'with max_per_second' do
            let(:max_per_second) { 10 }

            it 'sets the rule matcher service' do
              is_expected.to contain_exactly(
                Datadog::Tracing::Sampling::Span::Rule.new(
                  Datadog::Tracing::Sampling::Span::Matcher.new, rate_limit: max_per_second
                )
              )
            end

            context 'with an invalid value' do
              let(:max_per_second) { { 'bad' => 'max_per_second' } }

              it 'warns and returns nil' do
                expect(Datadog.logger).to receive(:warn).with(include(max_per_second.inspect) & include('Error'))
                is_expected.to be_nil
              end
            end
          end
        end
      end
    end
  end
end
