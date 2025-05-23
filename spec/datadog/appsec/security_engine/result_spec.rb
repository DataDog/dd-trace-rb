# frozen_string_literal: true

require 'datadog/appsec/spec_helper'

RSpec.describe Datadog::AppSec::SecurityEngine::Result do
  describe '.new' do
    context 'when initializing non-error result' do
      subject(:result) do
        described_class::Ok.new(
          events: [1],
          actions: { '2' => '2' },
          derivatives: { '3' => '3' },
          timeout: true,
          duration_ns: 400,
          duration_ext_ns: 500
        )
      end

      it { expect(result).to be_timeout }
      it { expect(result.events).to eq([1]) }
      it { expect(result.actions).to eq({ '2' => '2' }) }
      it { expect(result.derivatives).to eq({ '3' => '3' }) }
      it { expect(result.duration_ns).to eq(400) }
      it { expect(result.duration_ext_ns).to eq(500) }
    end

    context 'when initializing error result' do
      subject(:result) { described_class::Error.new(duration_ext_ns: 100) }

      it { expect(result).not_to be_timeout }
      it { expect(result.events).to eq([]) }
      it { expect(result.actions).to eq({}) }
      it { expect(result.derivatives).to eq({}) }
      it { expect(result.duration_ns).to eq(0) }
      it { expect(result.duration_ext_ns).to eq(100) }
    end
  end

  describe '#timeout?' do
    context 'when result indicates timeout' do
      subject(:result) do
        described_class::Ok.new(
          events: [], actions: {}, derivatives: {}, timeout: true, duration_ns: 0, duration_ext_ns: 0
        )
      end

      it { expect(result).to be_timeout }
    end

    context 'when result does not indicate timeout' do
      subject(:result) do
        described_class::Ok.new(
          events: [], actions: {}, derivatives: {}, timeout: false, duration_ns: 0, duration_ext_ns: 0
        )
      end

      it { expect(result).not_to be_timeout }
    end
  end

  describe '#match?' do
    context 'when result is a generic type' do
      subject(:result) do
        described_class::Base.new(
          events: [], actions: {}, derivatives: {}, timeout: false, duration_ns: 0, duration_ext_ns: 0
        )
      end

      it { expect { result.match? }.to raise_error NotImplementedError }
    end

    context 'when result is a "match" type' do
      subject(:result) do
        described_class::Match.new(
          events: [], actions: {}, derivatives: {}, timeout: false, duration_ns: 0, duration_ext_ns: 0
        )
      end

      it { expect(result).to be_match }
    end

    context 'when result is an "ok" type' do
      subject(:result) do
        described_class::Ok.new(
          events: [], actions: {}, derivatives: {}, timeout: false, duration_ns: 0, duration_ext_ns: 0
        )
      end

      it { expect(result).not_to be_match }
    end

    context 'when result is an "error" type' do
      subject(:result) { described_class::Error.new(duration_ext_ns: 0) }

      it { expect(result).not_to be_match }
    end
  end
end
