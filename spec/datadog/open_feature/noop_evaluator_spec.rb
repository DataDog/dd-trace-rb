# frozen_string_literal: true

require 'spec_helper'
require 'datadog/open_feature/noop_evaluator'

RSpec.describe Datadog::OpenFeature::NoopEvaluator do
  subject(:evaluator) { described_class.new(nil) }

  describe '#get_assignment' do
    let(:result) { evaluator.get_assignment('flag', nil, :string) }

    it 'returns provider not ready result' do
      expect(result).to be_error
      expect(result).not_to be_log
      expect(result.error_code).to eq('PROVIDER_NOT_READY')
      expect(result.error_message).to eq('Waiting for universal flag configuration')
      expect(result.reason).to eq('INITIALIZING')
    end
  end
end
