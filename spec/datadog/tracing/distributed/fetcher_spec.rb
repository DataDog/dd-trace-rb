# typed: false

require 'spec_helper'

require 'datadog/tracing/distributed/fetcher'
require 'datadog/tracing/span'

RSpec.describe Datadog::Tracing::Distributed::Fetcher do
  subject(:fetcher) { described_class.new(data) }

  let(:data) { {} }

  describe '#[]' do
    subject(:get) { fetcher[key] }
    let(:key) {}

    context 'with no value associated' do
      let(:key) { 'not present' }
      it { is_expected.to be_nil }
    end

    context 'with a value associated' do
      let(:data) { { key => 'value' } }
      it { is_expected.to eq('value') }
    end
  end

  describe '#id' do
    subject(:id) { fetcher.id(key, base: base) }
    let(:key) {}
    let(:base) { 10 }

    context 'with no value associated' do
      let(:key) { 'not present' }
      it { is_expected.to be_nil }
    end

    context 'with a value associated' do
      let(:key) { 'key' }

      [
        [nil, nil],
        ['not a number', nil],
        ['0', nil],
        ['', nil],

        # Larger than we allow
        [(Datadog::Tracing::Span::EXTERNAL_MAX_ID + 1).to_s, nil],

        # Negative number
        ['-100', -100 + (2**64)],

        # Allowed values
        [Datadog::Tracing::Span::RUBY_MAX_ID.to_s, Datadog::Tracing::Span::RUBY_MAX_ID],
        [Datadog::Tracing::Span::EXTERNAL_MAX_ID.to_s, Datadog::Tracing::Span::EXTERNAL_MAX_ID],
        ['1', 1],
        ['123456789', 123456789]
      ].each do |value, expected|
        context value.inspect do
          let(:data) { { key => value } }
          it { is_expected.to eq(expected) }
        end
      end

      # Base 16
      [
        # Larger than we allow
        # DEV: We truncate to 64-bit for base16
        [(Datadog::Tracing::Span::EXTERNAL_MAX_ID + 1).to_s(16), 1],
        [Datadog::Tracing::Span::EXTERNAL_MAX_ID.to_s(16), nil],

        [Datadog::Tracing::Span::RUBY_MAX_ID.to_s(16), Datadog::Tracing::Span::RUBY_MAX_ID],
        [(Datadog::Tracing::Span::EXTERNAL_MAX_ID - 1).to_s(16), Datadog::Tracing::Span::EXTERNAL_MAX_ID - 1],

        ['3e8', 1000],
        ['3E8', 1000],
        ['deadbeef', 3735928559],
        ['10000', 65536],

        ['invalid-base16', nil]
      ].each do |value, expected|
        context value.inspect do
          let(:data) { { key => value } }
          let(:base) { 16 }
          it { is_expected.to eq(expected) }
        end
      end
    end
  end

  describe '#number' do
    subject(:number) { fetcher.number(key, base: base) }
    let(:key) {}
    let(:base) { 10 }

    context 'with no value associated' do
      let(:key) { 'not present' }
      it { is_expected.to be_nil }
    end

    context 'with a value associated' do
      let(:key) { 'key' }

      [
        [nil, nil],
        ['not a number', nil],
        ['', nil],

        # Sampling priorities
        ['-1', -1],
        ['0', 0],
        ['1', 1],
        ['2', 2],

        # Allowed values
        [Datadog::Tracing::Span::RUBY_MAX_ID.to_s, Datadog::Tracing::Span::RUBY_MAX_ID],
        [(Datadog::Tracing::Span::RUBY_MAX_ID + 1).to_s, Datadog::Tracing::Span::RUBY_MAX_ID + 1],
        [Datadog::Tracing::Span::EXTERNAL_MAX_ID.to_s, Datadog::Tracing::Span::EXTERNAL_MAX_ID],
        [(Datadog::Tracing::Span::EXTERNAL_MAX_ID + 1).to_s, Datadog::Tracing::Span::EXTERNAL_MAX_ID + 1],
        ['-100', -100],
        ['100', 100],
        ['1000', 1000]
      ].each do |value, expected|
        context value.inspect do
          let(:data) { { key => value } }
          it { is_expected.to eq(expected) }
        end
      end

      # Base 16
      [
        # Larger than we allow
        # DEV: We truncate to 64-bit for base16, so the
        [Datadog::Tracing::Span::EXTERNAL_MAX_ID.to_s(16), 0],
        [(Datadog::Tracing::Span::EXTERNAL_MAX_ID + 1).to_s(16), 1],

        [Datadog::Tracing::Span::RUBY_MAX_ID.to_s(16), Datadog::Tracing::Span::RUBY_MAX_ID],
        [(Datadog::Tracing::Span::RUBY_MAX_ID + 1).to_s(16), Datadog::Tracing::Span::RUBY_MAX_ID + 1],

        ['3e8', 1000],
        ['3E8', 1000],
        ['deadbeef', 3735928559],
        ['10000', 65536],

        ['invalid-base16', nil]
      ].each do |value, expected|
        context value.inspect do
          let(:data) { { key => value } }
          let(:base) { 16 }
          it { is_expected.to eq(expected) }
        end
      end
    end
  end
end
