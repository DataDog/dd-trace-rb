# frozen_string_literal: true

require 'spec_helper'
require 'datadog/ai_guard'

RSpec.describe Datadog::AIGuard do
  describe '.enabled?' do
    context 'when AI Guard is enabled' do
      before do
        Datadog.configure { |c| c.ai_guard.enabled = true }
      end

      after do
        Datadog.configuration.reset!
      end

      it { expect(described_class.enabled?).to be(true) }
    end

    context 'when AI Guard is disabled' do
      before do
        Datadog.configure { |c| c.ai_guard.enabled = false }
      end

      after do
        Datadog.configuration.reset!
      end

      it { expect(described_class.enabled?).to be(false) }
    end
  end
end
