require 'spec_helper'

require 'datadog/appsec'

RSpec.describe Datadog::AppSec do
  describe '#default_setting?' do
    before { described_class.settings.send(:reset!) }
    after { described_class.settings.send(:reset!) }

    context 'when the configuration option is not configured' do
      it 'returns true' do
        expect(described_class.default_setting?(:enabled)).to eq(true)
      end
    end

    context 'when the configuration option is configured ' do
      it 'returns false' do
        described_class.configure do |c|
          c.enabled = true
        end
        expect(described_class.default_setting?(:enabled)).to eq(false)
      end
    end
  end
end
