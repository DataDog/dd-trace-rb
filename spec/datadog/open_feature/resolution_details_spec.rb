# frozen_string_literal: true

require 'spec_helper'
require 'datadog/open_feature/resolution_details'

RSpec.describe Datadog::OpenFeature::ResolutionDetails do
  describe '.build_success' do
    subject(:details) do
      described_class.build_success(
        value: 'test_value',
        variant: 'variant_key',
        allocation_key: 'alloc_key',
        do_log: true,
        reason: 'STATIC'
      )
    end

    it 'returns frozen success details with success fields populated' do
      expect(details).to be_frozen
      expect(details.value).to eq('test_value')
      expect(details.variant).to eq('variant_key')
      expect(details.allocation_key).to eq('alloc_key')
      expect(details.reason).to eq('STATIC')
      expect(details.error_code).to be_nil
      expect(details.error_message).to be_nil
      expect(details.error?).to be(false)
      expect(details.log?).to be(true)
      expect(details.flag_metadata).to eq({
        'allocationKey' => 'alloc_key',
        'doLog' => true
      })
      expect(details.extra_logging).to eq({})
    end
  end

  describe '.build_default' do
    subject(:details) do
      described_class.build_default(value: 'default_value', reason: 'DISABLED')
    end

    it 'returns frozen default details with minimal fields populated' do
      expect(details).to be_frozen
      expect(details.value).to eq('default_value')
      expect(details.reason).to eq('DISABLED')
      expect(details.variant).to be_nil
      expect(details.error_code).to be_nil
      expect(details.error_message).to be_nil
      expect(details.allocation_key).to be_nil
      expect(details.error?).to be(false)
      expect(details.log?).to be(false)
      expect(details.flag_metadata).to eq({})
      expect(details.extra_logging).to eq({})
    end
  end

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
        expect(details.variant).to be_nil
        expect(details.allocation_key).to be_nil
        expect(details.flag_metadata).to eq({})
        expect(details.extra_logging).to eq({})
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
