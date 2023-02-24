require 'spec_helper'

require 'datadog/tracing/metadata/tagging'

RSpec.describe Datadog::Tracing::Metadata::Tagging do
  subject(:test_object) { test_class.new }
  let(:test_class) { Class.new { include Datadog::Tracing::Metadata::Tagging } }

  describe '#get_tag' do
    subject(:get_tag) { test_object.get_tag(key) }
    let(:key) { 'test_tag' }
    let(:value) { 'test_value' }

    context 'when no tag exists' do
      it { is_expected.to be nil }
    end

    context 'when a meta tag exists' do
      before { test_object.send(:meta)[key] = value }
      it { is_expected.to be value }
    end

    context 'when a metric exists' do
      before { test_object.send(:metrics)[key] = value }
      it { is_expected.to be value }
    end
  end

  describe '#has_tag?' do
    subject(:has_tag?) { test_object.has_tag?(key) }
    let(:key) { 'test_tag' }
    let(:value) { 'test_value' }

    context 'when no tag exists' do
      it { is_expected.to be false }
    end

    context 'when a meta tag exists' do
      before { test_object.send(:meta)[key] = value }
      it { is_expected.to be true }
    end

    context 'when a metric exists' do
      before { test_object.send(:metrics)[key] = value }
      it { is_expected.to be true }
    end
  end

  describe '#set_tag' do
    subject(:set_tag) { test_object.set_tag(key, value) }

    shared_examples_for 'meta tag' do
      let(:old_value) { nil }

      it 'sets a tag' do
        expect { set_tag }.to change { test_object.send(:meta)[key] }
          .from(old_value)
          .to(value.to_s)
      end

      it 'does not set a metric' do
        expect { set_tag }.to_not change { test_object.send(:metrics)[key] }
          .from(old_value)
      end
    end

    shared_examples_for 'metric tag' do
      let(:old_value) { nil }

      it 'does not set a tag' do
        expect { set_tag }.to_not change { test_object.send(:meta)[key] }
          .from(old_value)
      end

      it 'sets a metric' do
        expect { set_tag }.to change { test_object.send(:metrics)[key] }
          .from(old_value)
          .to(value.to_f)
      end
    end

    context "given #{Datadog::Tracing::Metadata::Ext::NET::TAG_HOSTNAME}" do
      let(:key) { Datadog::Tracing::Metadata::Ext::NET::TAG_HOSTNAME }

      context 'as a numeric value' do
        let(:value) { 1 }
        it_behaves_like 'meta tag'
      end
    end

    context "given #{Datadog::Tracing::Metadata::Ext::Distributed::TAG_ORIGIN}" do
      let(:key) { Datadog::Tracing::Metadata::Ext::Distributed::TAG_ORIGIN }

      context 'as a numeric value' do
        let(:value) { 2 }
        it_behaves_like 'meta tag'
      end
    end

    context "given #{Datadog::Tracing::Metadata::Ext::HTTP::TAG_STATUS_CODE}" do
      let(:key) { Datadog::Tracing::Metadata::Ext::HTTP::TAG_STATUS_CODE }

      context 'as a numeric value' do
        let(:value) { 200 }
        it_behaves_like 'meta tag'
      end
    end

    context "given #{Datadog::Core::Environment::Ext::TAG_VERSION}" do
      let(:key) { Datadog::Core::Environment::Ext::TAG_VERSION }

      context 'as a numeric value' do
        let(:value) { 3 }
        it_behaves_like 'meta tag'
      end
    end

    context 'given a numeric tag' do
      let(:key) { 'process_pid' }
      let(:value) { 123 }

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
        before { test_object.set_tag(key, 'old value') }

        it 'removes the tag' do
          expect { set_tag }.to change { test_object.send(:meta)[key] }
            .from('old value')
            .to(nil)
        end

        it 'adds a new metric' do
          expect { set_tag }.to change { test_object.send(:metrics)[key] }
            .from(nil)
            .to(value)
        end
      end

      context 'that conflicts with an existing metric' do
        before { test_object.set_metric(key, 404) }

        it 'replaces the metric' do
          expect { set_tag }.to change { test_object.send(:metrics)[key] }
            .from(404)
            .to(value)

          expect(test_object.send(:meta)[key]).to be nil
        end
      end
    end

    context 'given a string tag that is not in UTF-8' do
      let(:key) { 'key'.encode(Encoding::ASCII) }
      let(:value) { 'value'.encode(Encoding::ASCII) }
      let(:meta) { test_object.send(:meta) }

      it 'converts tag value to UTF-8' do
        set_tag

        expect(meta.keys.first).to eq(key) & have_attributes(encoding: Encoding::UTF_8)
        expect(meta[key]).to eq(value) & have_attributes(encoding: Encoding::UTF_8)
      end
    end
  end

  describe '#set_tags' do
    subject(:set_tags) { test_object.set_tags(tags) }

    context 'with empty hash' do
      let(:tags) { {} }

      it 'does not change tags' do
        expect(test_object).to_not receive(:set_tag)
        set_tags
      end
    end

    context 'with multiple tags' do
      let(:tags) { { 'user.id' => 123, 'user.domain' => 'datadog.com' } }

      it 'sets the tags from hash keys' do
        expect { set_tags }
          .to change { tags.map { |k, _| test_object.get_tag(k) } }
          .from([nil, nil]).to([123, 'datadog.com'])
      end
    end

    context 'with nested hashes' do
      let(:tags) do
        {
          'user' => {
            'id' => 123
          }
        }
      end

      it 'does not support it - it sets stringified nested hash as value' do
        expect { set_tags }.to change { test_object.get_tag('user') }.from(nil).to('{"id"=>123}')
      end
    end
  end

  describe '#clear_tag' do
    subject(:clear_tag) { test_object.clear_tag(key) }

    let(:key) { 'key' }
    let(:value) { 'value' }

    before { test_object.set_tag(key, value) }

    it do
      expect { clear_tag }.to change { test_object.get_tag(key) }.from(value).to(nil)
    end

    it 'removes value, instead of setting to nil, to ensure correct deserialization by agent' do
      clear_tag
      expect(test_object.send(:meta)).to_not have_key(key)
    end
  end

  describe '#get_metric' do
    subject(:get_metric) { test_object.get_metric(key) }

    let(:key) { 'key' }

    context 'with no metrics' do
      it { is_expected.to be_nil }
    end

    context 'with a metric' do
      let(:value) { 1.0 }

      before { test_object.set_metric(key, value) }

      it { is_expected.to eq(1.0) }
    end

    context 'with a tag' do
      let(:value) { 'tag' }

      before { test_object.set_tag(key, value) }

      it { is_expected.to eq('tag') }
    end
  end

  describe '#set_metric' do
    subject(:set_metric) { test_object.set_metric(key, value) }

    let(:key) { 'key' }

    let(:metrics) { test_object.send(:metrics) }
    let(:metric) { metrics[key] }

    shared_examples 'a metric' do |value, expected|
      let(:value) { value }

      it do
        subject
        expect(metric).to eq(expected)
      end
    end

    context 'with a valid value' do
      context 'with an integer' do
        it_behaves_like 'a metric', 0, 0.0
      end

      context 'with a float' do
        it_behaves_like 'a metric', 12.34, 12.34
      end

      context 'with a number as string' do
        it_behaves_like 'a metric', '12.34', 12.34
      end
    end

    context 'with an invalid value' do
      context 'with nil' do
        it_behaves_like 'a metric', nil, nil
      end

      context 'with a string' do
        it_behaves_like 'a metric', 'foo', nil
      end

      context 'with a complex object' do
        it_behaves_like 'a metric', [], nil
      end
    end

    context 'given a string tag that is not in UTF-8' do
      let(:key) { 'key'.encode(Encoding::ASCII) }
      let(:value) { 123 }

      it 'converts key to UTF-8' do
        set_metric

        expect(metrics.keys.first).to eq(key) & have_attributes(encoding: Encoding::UTF_8)
        expect(metrics[key]).to eq(value)
      end
    end
  end

  describe '#clear_metric' do
    subject(:clear_metric) { test_object.clear_metric(key) }

    let(:key) { 'key' }
    let(:value) { 1.0 }

    before { test_object.set_metric(key, value) }

    it do
      expect { clear_metric }.to change { test_object.get_metric(key) }.from(value).to(nil)
    end

    it 'removes value, instead of setting to nil, to ensure correct deserialization by agent' do
      clear_metric
      expect(test_object.send(:metrics)).to_not have_key(key)
    end
  end
end
