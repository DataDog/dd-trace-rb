# frozen_string_literal: true

require 'datadog/appsec/spec_helper'

RSpec.describe Datadog::AppSec do
  describe '#default_setting?' do
    before { described_class.settings.send(:reset!) }
    after { described_class.settings.send(:reset!) }

    context 'when the configuration option is not configured' do
      it 'returns true' do
        expect(described_class.send(:default_setting?, :enabled)).to eq(true)
      end
    end

    context 'when the configuration option is configured ' do
      it 'returns false' do
        described_class.configure do |c|
          c.enabled = true
        end
        expect(described_class.send(:default_setting?, :enabled)).to eq(false)
      end
    end
  end
end
