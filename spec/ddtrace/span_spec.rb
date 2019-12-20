require 'spec_helper'
require 'ddtrace/ext/forced_tracing'
require 'ddtrace/span'

RSpec.describe Datadog::Span do
  subject(:span) { described_class.new(tracer, name, context: context) }
  let(:tracer) { get_test_tracer }
  let(:context) { Datadog::Context.new }
  let(:name) { 'my.span' }

  describe '#finish' do
    subject(:finish) { span.finish }

    context 'when an error occurs while closing the span on the context' do
      include_context 'health metrics'

      let(:error) { error_class.new }
      let(:error_class) { stub_const('SpanCloseError', Class.new(StandardError)) }

      RSpec::Matchers.define :a_record_finish_error do |error|
        match { |actual| actual == "error recording finished trace: #{error}" }
      end

      before do
        allow(Datadog::Logger.log).to receive(:debug)
        allow(context).to receive(:close_span)
          .with(span)
          .and_raise(error)
        finish
      end

      it 'logs a debug message' do
        expect(Datadog::Logger.log).to have_received(:debug)
          .with(a_record_finish_error(error))
      end

      it 'sends a span finish error metric' do
        expect(health_metrics).to have_received(:error_span_finish)
          .with(1, tags: ["error:#{error_class.name}"])
      end
    end
  end

  describe '#clear_tag' do
    subject(:clear_tag) { span.clear_tag(key) }
    let(:key) { 'key' }

    before { span.set_tag(key, value) }
    let(:value) { 'value' }

    it do
      expect { subject }.to change { span.get_tag(key) }.from(value).to(nil)
    end

    it 'removes value, instead of setting to nil, to ensure correct deserialization by agent' do
      subject
      expect(span.instance_variable_get(:@meta)).to_not have_key(key)
    end
  end

  describe '#clear_metric' do
    subject(:clear_metric) { span.clear_metric(key) }
    let(:key) { 'key' }

    before { span.set_metric(key, value) }
    let(:value) { 1.0 }

    it do
      expect { subject }.to change { span.get_metric(key) }.from(value).to(nil)
    end

    it 'removes value, instead of setting to nil, to ensure correct deserialization by agent' do
      subject
      expect(span.instance_variable_get(:@metrics)).to_not have_key(key)
    end
  end

  describe '#set_tag' do
    subject(:set_tag) { span.set_tag(key, value) }

    shared_examples_for 'meta tag' do
      let(:old_value) { nil }

      it 'sets a tag' do
        expect { set_tag }.to change { span.instance_variable_get(:@meta)[key] }
          .from(old_value)
          .to(value.to_s)
      end

      it 'does not set a metric' do
        expect { set_tag }.to_not change { span.instance_variable_get(:@metrics)[key] }
          .from(old_value)
      end
    end

    shared_examples_for 'metric tag' do
      let(:old_value) { nil }

      it 'does not set a tag' do
        expect { set_tag }.to_not change { span.instance_variable_get(:@meta)[key] }
          .from(old_value)
      end

      it 'sets a metric' do
        expect { set_tag }.to change { span.instance_variable_get(:@metrics)[key] }
          .from(old_value)
          .to(value.to_f)
      end
    end

    context 'given a numeric tag' do
      let(:key) { 'http.status_code' }
      let(:value) { 200 }

      context 'which is an integer' do
        context 'that exceeds the upper limit' do
          let(:value) { described_class::NUMERIC_TAG_SIZE_RANGE.max.to_i + 1 }
          it_behaves_like 'meta tag'
        end

        context 'at the upper limit' do
          let(:value) { described_class::NUMERIC_TAG_SIZE_RANGE.max.to_i }
          it_behaves_like 'metric tag'
        end

        context 'at the lower limit' do
          let(:value) { described_class::NUMERIC_TAG_SIZE_RANGE.min.to_i }
          it_behaves_like 'metric tag'
        end

        context 'that is below the lower limit' do
          let(:value) { described_class::NUMERIC_TAG_SIZE_RANGE.min.to_i - 1 }
          it_behaves_like 'meta tag'
        end
      end

      context 'which is a float' do
        context 'that exceeds the upper limit' do
          let(:value) { described_class::NUMERIC_TAG_SIZE_RANGE.max.to_f + 1.0 }
          it_behaves_like 'metric tag'
        end

        context 'at the upper limit' do
          let(:value) { described_class::NUMERIC_TAG_SIZE_RANGE.max.to_f }
          it_behaves_like 'metric tag'
        end

        context 'at the lower limit' do
          let(:value) { described_class::NUMERIC_TAG_SIZE_RANGE.min.to_f }
          it_behaves_like 'metric tag'
        end

        context 'that is below the lower limit' do
          let(:value) { described_class::NUMERIC_TAG_SIZE_RANGE.min.to_f - 1.0 }
          it_behaves_like 'metric tag'
        end
      end

      context 'that conflicts with an existing tag' do
        before { span.set_tag(key, 'old value') }

        it 'removes the tag' do
          expect { set_tag }.to change { span.instance_variable_get(:@meta)[key] }
            .from('old value')
            .to(nil)
        end

        it 'adds a new metric' do
          expect { set_tag }.to change { span.instance_variable_get(:@metrics)[key] }
            .from(nil)
            .to(value)
        end
      end

      context 'that conflicts with an existing metric' do
        before { span.set_metric(key, 404) }

        it 'replaces the metric' do
          expect { set_tag }.to change { span.instance_variable_get(:@metrics)[key] }
            .from(404)
            .to(value)

          expect(span.instance_variable_get(:@meta)[key]).to be nil
        end
      end
    end

    # context 'that conflicts with a metric' do
    #   it 'removes the metric'
    #   it 'adds a new tag'
    # end

    context 'given Datadog::Ext::Analytics::TAG_ENABLED' do
      let(:key) { Datadog::Ext::Analytics::TAG_ENABLED }
      let(:value) { true }

      before { set_tag }

      it 'sets the analytics sample rate' do
        # Both should return the same tag
        expect(span.get_metric(Datadog::Ext::Analytics::TAG_SAMPLE_RATE)).to eq(1.0)
        expect(span.get_tag(Datadog::Ext::Analytics::TAG_SAMPLE_RATE)).to be 1.0
      end
    end

    context 'given Datadog::Ext::Analytics::TAG_SAMPLE_RATE' do
      let(:key) { Datadog::Ext::Analytics::TAG_SAMPLE_RATE }
      let(:value) { 0.5 }

      before { set_tag }

      it 'sets the analytics sample rate' do
        # Both should return the same tag
        expect(span.get_metric(Datadog::Ext::Analytics::TAG_SAMPLE_RATE)).to eq(value)
        expect(span.get_tag(Datadog::Ext::Analytics::TAG_SAMPLE_RATE)).to be value
      end
    end

    shared_examples 'setting sampling priority tag' do |key, expected_value|
      before { set_tag }

      context "given #{key}" do
        let(:key) { key }

        context 'with nil value' do
          # This could be `nil`, or any other value, as long as it isn't "false"
          let(:value) { nil }

          it 'sets the correct sampling priority' do
            expect(context.sampling_priority).to eq(expected_value)
          end

          it 'does not set a tag' do
            expect(span.get_tag(key)).to be nil
          end
        end

        context 'with true value' do
          # We only check for `== false`, but test with `true` to be sure it works
          let(:value) { true }

          it 'sets the correct sampling priority' do
            expect(context.sampling_priority).to eq(expected_value)
          end

          it 'does not set a tag' do
            expect(span.get_tag(key)).to be nil
          end
        end

        context 'with false value' do
          let(:value) { false }

          it 'does not set the sampling priority' do
            expect(context.sampling_priority).to_not eq(expected_value)
          end

          it 'does not set a tag' do
            expect(span.get_tag(key)).to be nil
          end
        end
      end
    end

    # TODO: Remove when ForcedTracing is fully deprecated
    it_behaves_like('setting sampling priority tag',
                    Datadog::Ext::ForcedTracing::TAG_KEEP,
                    Datadog::Ext::Priority::USER_KEEP)
    it_behaves_like('setting sampling priority tag',
                    Datadog::Ext::ForcedTracing::TAG_DROP,
                    Datadog::Ext::Priority::USER_REJECT)

    it_behaves_like('setting sampling priority tag',
                    Datadog::Ext::ManualTracing::TAG_KEEP,
                    Datadog::Ext::Priority::USER_KEEP)
    it_behaves_like('setting sampling priority tag',
                    Datadog::Ext::ManualTracing::TAG_DROP,
                    Datadog::Ext::Priority::USER_REJECT)
  end
end
