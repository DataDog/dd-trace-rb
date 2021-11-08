# typed: ignore
require 'spec_helper'

require 'ddtrace/tagging/manual_tracing'

RSpec.describe Datadog::SpanOperation::ManualTracing do
  subject(:test_object) { test_class.new }

  describe '#set_tag' do
    subject(:set_tag) { test_object.set_tag(key, value) }

    before do
      allow(Datadog::ManualTracing).to receive(:keep)
      allow(Datadog::ManualTracing).to receive(:drop)
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
          prepend Datadog::Tagging::ManualTracing
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
            expect(Datadog::ManualTracing).to_not have_received(:keep)
            expect(Datadog::ManualTracing).to_not have_received(:drop)
            expect(span).to have_received(:set_tag)
              .with(key, value)
          end
        end

        context 'TAG_KEEP with' do
          let(:key) { Datadog::Ext::ManualTracing::TAG_KEEP }

          context 'true' do
            let(:value) { true }

            it do
              expect(Datadog::ManualTracing).to have_received(:keep)
                .with(test_object)
              expect(Datadog::ManualTracing).to_not have_received(:drop)
              expect(span).to_not have_received(:set_tag)
            end
          end

          context 'false' do
            let(:value) { false }

            it do
              expect(Datadog::ManualTracing).to_not have_received(:keep)
              expect(Datadog::ManualTracing).to_not have_received(:drop)
              expect(span).to_not have_received(:set_tag)
            end
          end

          context 'nil' do
            let(:value) { nil }

            it do
              expect(Datadog::ManualTracing).to have_received(:keep)
                .with(test_object)
              expect(Datadog::ManualTracing).to_not have_received(:drop)
              expect(span).to_not have_received(:set_tag)
            end
          end
        end

        context 'TAG_DROP with' do
          let(:key) { Datadog::Ext::ManualTracing::TAG_DROP }

          context 'true' do
            let(:value) { true }

            it do
              expect(Datadog::ManualTracing).to_not have_received(:keep)
              expect(Datadog::ManualTracing).to have_received(:drop)
                .with(test_object)
              expect(span).to_not have_received(:set_tag)
            end
          end

          context 'false' do
            let(:value) { false }

            it do
              expect(Datadog::ManualTracing).to_not have_received(:keep)
              expect(Datadog::ManualTracing).to_not have_received(:drop)
              expect(span).to_not have_received(:set_tag)
            end
          end

          context 'nil' do
            let(:value) { nil }

            it do
              expect(Datadog::ManualTracing).to_not have_received(:keep)
              expect(Datadog::ManualTracing).to have_received(:drop)
                .with(test_object)
              expect(span).to_not have_received(:set_tag)
            end
          end
        end
      end
    end
  end
end
