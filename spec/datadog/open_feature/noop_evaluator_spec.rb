# frozen_string_literal: true

require 'spec_helper'
require 'datadog/open_feature/noop_evaluator'

RSpec.describe Datadog::OpenFeature::NoopEvaluator do
  subject(:evaluator) { described_class.new(nil) }

  describe '#get_assignment' do
    it 'returns provider not ready result' do
      expect(evaluator.get_assignment('flag', nil, :string, Time.now.utc.to_i)).to eq(
        error_code: 'PROVIDER_NOT_READY',
        error_message: 'Waiting for universal flag configuration',
        reason: 'INITIALIZING'
      )
    end
  end
end

