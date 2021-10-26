# typed: ignore
require 'spec_helper'
require 'ddtrace/span_operation'

# rubocop:disable RSpec/EmptyExampleGroup
RSpec.describe Datadog::SpanOperation do
  # TODO
end
# rubocop:enable RSpec/EmptyExampleGroup

RSpec.describe Datadog::SpanOperation::Analytics do
  subject(:test_object) { test_class.new }

  describe '#set_tag' do
    subject(:set_tag) { test_object.set_tag(key, value) }

    before do
      allow(Datadog::Analytics).to receive(:set_sample_rate)
      set_tag
    end

    context 'when #set_tag is defined on the class' do
      let(:test_class) do
        Class.new do
          prepend Datadog::SpanOperation::Analytics

          # Define this method here to prove it doesn't
          # override behavior in Datadog::Analytics::Span.
          def set_tag(key, value)
            [key, value]
          end
        end
      end

      context 'and is given' do
        context 'some kind of tag' do
          let(:key) { 'my.tag' }
          let(:value) { 'my.value' }

          it 'calls the super #set_tag' do
            is_expected.to eq([key, value])
          end
        end

        context 'TAG_ENABLED with' do
          let(:key) { Datadog::Ext::Analytics::TAG_ENABLED }

          context 'true' do
            let(:value) { true }

            it do
              expect(Datadog::Analytics).to have_received(:set_sample_rate)
                .with(test_object, Datadog::Ext::Analytics::DEFAULT_SAMPLE_RATE)
            end
          end

          context 'false' do
            let(:value) { false }

            it do
              expect(Datadog::Analytics).to have_received(:set_sample_rate)
                .with(test_object, 0.0)
            end
          end

          context 'nil' do
            let(:value) { nil }

            it do
              expect(Datadog::Analytics).to have_received(:set_sample_rate)
                .with(test_object, 0.0)
            end
          end
        end

        context 'TAG_SAMPLE_RATE with' do
          let(:key) { Datadog::Ext::Analytics::TAG_SAMPLE_RATE }

          context 'a Float' do
            let(:value) { 0.5 }

            it do
              expect(Datadog::Analytics).to have_received(:set_sample_rate)
                .with(test_object, value)
            end
          end

          context 'a String' do
            let(:value) { '0.5' }

            it do
              expect(Datadog::Analytics).to have_received(:set_sample_rate)
                .with(test_object, value)
            end
          end

          context 'nil' do
            let(:value) { nil }

            it do
              expect(Datadog::Analytics).to have_received(:set_sample_rate)
                .with(test_object, value)
            end
          end
        end
      end
    end
  end
end

RSpec.describe Datadog::SpanOperation::ForcedTracing do
  subject(:test_object) { test_class.new }

  describe '#set_tag' do
    subject(:set_tag) { test_object.set_tag(key, value) }

    before do
      allow(Datadog::ForcedTracing).to receive(:keep)
      allow(Datadog::ForcedTracing).to receive(:drop)
      set_tag
    end

    context 'when #set_tag is defined on the class' do
      let(:span) do
        instance_double(Datadog::Span).tap do |span|
          allow(span).to receive(:set_tag)
        end
      end

      let(:test_class) do
        s = span

        klass = Class.new do
          prepend Datadog::SpanOperation::ForcedTracing
        end

        klass.tap do
          # Define this method here to prove it doesn't
          # override behavior in Datadog::Analytics::Span.
          klass.send(:define_method, :set_tag) do |key, value|
            s.set_tag(key, value)
          end
        end
      end

      context 'and is given' do
        context 'some kind of tag' do
          let(:key) { 'my.tag' }
          let(:value) { 'my.value' }

          it 'calls the super #set_tag' do
            expect(Datadog::ForcedTracing).to_not have_received(:keep)
            expect(Datadog::ForcedTracing).to_not have_received(:drop)
            expect(span).to have_received(:set_tag)
              .with(key, value)
          end
        end

        context 'TAG_KEEP with' do
          let(:key) { Datadog::Ext::ManualTracing::TAG_KEEP }

          context 'true' do
            let(:value) { true }

            it do
              expect(Datadog::ForcedTracing).to have_received(:keep)
                .with(test_object)
              expect(Datadog::ForcedTracing).to_not have_received(:drop)
              expect(span).to_not have_received(:set_tag)
            end
          end

          context 'false' do
            let(:value) { false }

            it do
              expect(Datadog::ForcedTracing).to_not have_received(:keep)
              expect(Datadog::ForcedTracing).to_not have_received(:drop)
              expect(span).to_not have_received(:set_tag)
            end
          end

          context 'nil' do
            let(:value) { nil }

            it do
              expect(Datadog::ForcedTracing).to have_received(:keep)
                .with(test_object)
              expect(Datadog::ForcedTracing).to_not have_received(:drop)
              expect(span).to_not have_received(:set_tag)
            end
          end
        end

        context 'TAG_DROP with' do
          let(:key) { Datadog::Ext::ManualTracing::TAG_DROP }

          context 'true' do
            let(:value) { true }

            it do
              expect(Datadog::ForcedTracing).to_not have_received(:keep)
              expect(Datadog::ForcedTracing).to have_received(:drop)
                .with(test_object)
              expect(span).to_not have_received(:set_tag)
            end
          end

          context 'false' do
            let(:value) { false }

            it do
              expect(Datadog::ForcedTracing).to_not have_received(:keep)
              expect(Datadog::ForcedTracing).to_not have_received(:drop)
              expect(span).to_not have_received(:set_tag)
            end
          end

          context 'nil' do
            let(:value) { nil }

            it do
              expect(Datadog::ForcedTracing).to_not have_received(:keep)
              expect(Datadog::ForcedTracing).to have_received(:drop)
                .with(test_object)
              expect(span).to_not have_received(:set_tag)
            end
          end
        end
      end
    end
  end
end
