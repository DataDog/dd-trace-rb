# frozen_string_literal: true

require 'spec_helper'

require 'set'
require 'json'
require 'digest'

require 'datadog/open_feature/hooks/span_enrichment_hook'

RSpec.describe Datadog::OpenFeature::Hooks::SpanEnrichmentHook::SpanEnrichmentState do
  subject(:span_enrichment_state) { described_class.new }

  let(:codec) { Datadog::OpenFeature::Hooks::SpanEnrichmentHook::Codec }

  describe '#add_serial_id' do
    it 'accumulates and dedupes serial ids' do
      span_enrichment_state.add_serial_id(100)
      span_enrichment_state.add_serial_id(100)
      span_enrichment_state.add_serial_id(108)

      tags = span_enrichment_state.to_span_tags
      expect(tags['ffe_flags_enc']).to eq(codec.encode_delta_varint(Set[100, 108]))
    end

    it 'enforces the 200 serial id limit' do
      250.times { |i| span_enrichment_state.add_serial_id(i) }
      decoded = span_enrichment_state.to_span_tags['ffe_flags_enc'].unpack1('m0').bytes
      # 200 single-byte deltas (all ids < 128 so one byte each, deltas of 1).
      count = decoded.count { |b| (b & 0x80).zero? }
      expect(count).to eq(200)
    end
  end

  describe '#add_subject' do
    it 'emits ffe_subjects_enc as a JSON object of {sha256hex => base64}' do
      span_enrichment_state.add_serial_id(100)
      span_enrichment_state.add_subject('user-123', 100)

      subjects = JSON.parse(span_enrichment_state.to_span_tags['ffe_subjects_enc'])
      hashed = Digest::SHA256.hexdigest('user-123')
      expect(subjects.keys).to eq([hashed])
      expect(subjects[hashed]).to eq(codec.encode_delta_varint(Set[100]))
    end

    it 'enforces the 10 subject limit' do
      span_enrichment_state.add_serial_id(1)
      12.times { |i| span_enrichment_state.add_subject("user-#{i}", 1) }
      subjects = JSON.parse(span_enrichment_state.to_span_tags['ffe_subjects_enc'])
      expect(subjects.size).to eq(10)
    end

    it 'enforces the 20 experiments-per-subject limit' do
      25.times { |i| span_enrichment_state.add_serial_id(i) }
      25.times { |i| span_enrichment_state.add_subject('user-123', i) }
      subjects = JSON.parse(span_enrichment_state.to_span_tags['ffe_subjects_enc'])
      hashed = Digest::SHA256.hexdigest('user-123')
      decoded = subjects[hashed].unpack1('m0').bytes
      count = decoded.count { |b| (b & 0x80).zero? }
      expect(count).to eq(20)
    end
  end

  describe '#add_default' do
    it 'emits ffe_runtime_defaults as a JSON object string' do
      span_enrichment_state.add_default('flag-a', 'control')
      defaults = JSON.parse(span_enrichment_state.to_span_tags['ffe_runtime_defaults'])
      expect(defaults).to eq('flag-a' => 'control')
    end

    it 'JSON-encodes object defaults (not [object Object]/inspect)' do
      span_enrichment_state.add_default('flag-obj', {'feature' => 'enabled', 'count' => 42})
      defaults = JSON.parse(span_enrichment_state.to_span_tags['ffe_runtime_defaults'])
      expect(JSON.parse(defaults['flag-obj'])).to eq('feature' => 'enabled', 'count' => 42)
    end

    it 'is first-wins for a repeated flag key' do
      span_enrichment_state.add_default('flag-a', 'first')
      span_enrichment_state.add_default('flag-a', 'second')
      defaults = JSON.parse(span_enrichment_state.to_span_tags['ffe_runtime_defaults'])
      expect(defaults['flag-a']).to eq('first')
    end

    it 'truncates default values longer than 64 chars' do
      span_enrichment_state.add_default('flag-a', 'x' * 100)
      defaults = JSON.parse(span_enrichment_state.to_span_tags['ffe_runtime_defaults'])
      expect(defaults['flag-a'].length).to eq(64)
    end

    it 'enforces the 5 defaults limit' do
      7.times { |i| span_enrichment_state.add_default("flag-#{i}", 'v') }
      defaults = JSON.parse(span_enrichment_state.to_span_tags['ffe_runtime_defaults'])
      expect(defaults.size).to eq(5)
    end
  end

  describe '#has_data?' do
    it 'is false when empty' do
      expect(span_enrichment_state.has_data?).to be(false)
    end

    it 'is true with serial ids' do
      span_enrichment_state.add_serial_id(1)
      expect(span_enrichment_state.has_data?).to be(true)
    end

    it 'is true with defaults' do
      span_enrichment_state.add_default('flag-a', 'v')
      expect(span_enrichment_state.has_data?).to be(true)
    end
  end

  describe '#to_span_tags' do
    it 'omits ffe_flags_enc when there are no serial ids' do
      span_enrichment_state.add_default('flag-a', 'v')
      expect(span_enrichment_state.to_span_tags).not_to have_key('ffe_flags_enc')
    end
  end
end
