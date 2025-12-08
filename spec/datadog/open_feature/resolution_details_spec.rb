# frozen_string_literal: true

require 'spec_helper'
require 'datadog/open_feature/resolution_details'

RSpec.describe Datadog::OpenFeature::ResolutionDetails do
  describe '.build_error' do
    context 'when reason is not provided' do
      subject(:details) { described_class.build_error(value: 'fallback', error_code: 'CODE', error_message: 'Oops') }

      it 'returns frozen error details with default reason' do
        expect(details).to be_frozen
        expect(details.value).to eq('fallback')
        expect(details.error_code).to eq('CODE')
        expect(details.error_message).to eq('Oops')
        expect(details.reason).to eq('ERROR')
        expect(details.error?).to be(true)
        expect(details.log?).to be(false)
      end
    end

    context 'when reason is provided' do
      subject(:details) do
        described_class.build_error(value: 'fallback', error_code: 'CODE', error_message: 'Oops', reason: 'CUSTOM')
      end

      it 'returns error details with given reason' do
        expect(details.reason).to eq('CUSTOM')
      end
    end
  end
end
