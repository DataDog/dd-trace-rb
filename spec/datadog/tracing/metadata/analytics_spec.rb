require 'spec_helper'

require 'datadog/tracing/metadata/analytics'
require 'datadog/tracing/metadata/ext'

RSpec.describe Datadog::Tracing::Metadata::Analytics do
  subject(:test_object) { test_class.new }

  describe '#set_tag' do
    subject(:set_tag) { test_object.set_tag(key, value) }

    before do
      allow(Datadog::Tracing::Analytics).to receive(:set_sample_rate)
      set_tag
    end

    context 'when #set_tag is defined on the class' do
      let(:test_class) do
        Class.new do
          prepend Datadog::Tracing::Metadata::Analytics

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
          let(:key) { Datadog::Tracing::Metadata::Ext::Analytics::TAG_ENABLED }

          context 'true' do
            let(:value) { true }

            it do
              expect(Datadog::Tracing::Analytics).to have_received(:set_sample_rate)
                .with(test_object, Datadog::Tracing::Metadata::Ext::Analytics::DEFAULT_SAMPLE_RATE)
            end
          end

          context 'false' do
            let(:value) { false }

            it do
              expect(Datadog::Tracing::Analytics).to have_received(:set_sample_rate)
                .with(test_object, 0.0)
            end
          end

          context 'nil' do
            let(:value) { nil }

            it do
              expect(Datadog::Tracing::Analytics).to have_received(:set_sample_rate)
                .with(test_object, 0.0)
            end
          end
        end

        context 'TAG_SAMPLE_RATE with' do
          let(:key) { Datadog::Tracing::Metadata::Ext::Analytics::TAG_SAMPLE_RATE }

          context 'a Float' do
            let(:value) { 0.5 }

            it do
              expect(Datadog::Tracing::Analytics).to have_received(:set_sample_rate)
                .with(test_object, value)
            end
          end

          context 'a String' do
            let(:value) { '0.5' }

            it do
              expect(Datadog::Tracing::Analytics).to have_received(:set_sample_rate)
                .with(test_object, value)
            end
          end

          context 'nil' do
            let(:value) { nil }

            it do
              expect(Datadog::Tracing::Analytics).to have_received(:set_sample_rate)
                .with(test_object, value)
            end
          end
        end
      end
    end
  end
end
