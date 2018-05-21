require 'spec_helper'

require 'ddtrace/utils/base_tag_converter'
require 'ddtrace/utils/tagger'

RSpec.describe Datadog::Utils::Tagger do
  describe '.tag' do
    let(:span) { double(:span, get_tag: nil, set_tag: nil) }
    let(:converted_value) { 'converted_value' }
    let(:converted_name) { 'converted_name' }
    let(:converter) { double(:converter, name: converted_name, value: converted_value) }

    context 'whitelist is empty' do
      let(:whitelist) { [] }

      it "doesn't convert entry name" do
        expect(converter).not_to receive(:name)
        expect(span).not_to receive(:get_tag)

        described_class.tag(span, whitelist, converter, {})
      end

      it "doesn't check if tag is set" do
        expect(span).not_to receive(:get_tag)

        described_class.tag(span, whitelist, converter, {})
      end
    end

    context 'whitelist contains entry names' do
      let(:whitelist) { %w[entry entry_2] }

      it 'converts every entry name' do
        expect(converter).to receive(:name).with('entry')
        expect(converter).to receive(:name).with('entry_2')

        described_class.tag(span, whitelist, converter, {})
      end

      it 'checks if tag is set' do
        expect(span).to receive(:get_tag).with(converted_name)

        described_class.tag(span, whitelist, converter, {})
      end

      context 'tag is set' do
        let(:tag) { double(:tag) }

        before do
          allow(span).to receive(:get_tag).and_return(tag)
        end

        it "doesn't convert entry value" do
          expect(converter).not_to receive(:value)

          described_class.tag(span, whitelist, converter, {})
        end
      end

      context 'tag is not set' do
        let(:entry_value) { 'entry_value' }
        let (:data) { { entry: entry_value } }

        it 'converts entry value' do
          expect(converter).to receive(:value).with('entry', data)

          described_class.tag(span, whitelist, converter, data)
        end

        it 'tags converted entry value' do
          expect(span).to receive(:set_tag).with(converted_name, converted_value)

          described_class.tag(span, whitelist, converter, data)
        end
      end
    end
  end
end
