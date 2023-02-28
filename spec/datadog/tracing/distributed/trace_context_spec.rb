require 'spec_helper'

require 'datadog/tracing/distributed/trace_context'
require 'datadog/tracing/trace_digest'

RSpec.shared_examples 'Trace Context distributed format' do
  subject(:datadog) { described_class.new(fetcher: fetcher_class) }
  let(:fetcher_class) { Datadog::Tracing::Distributed::Fetcher }

  let(:prepare_key) { defined?(super) ? super() : proc { |key| key } }

  describe '#inject!' do
    subject!(:inject!) { datadog.inject!(digest, data) }
    let(:data) { {} }

    let(:traceparent) { data['traceparent'] }
    let(:tracestate) { data['tracestate'] }
    let(:trace_flags) { traceparent[53..54] }

    context 'with a nil digest' do
      let(:digest) { nil }
      it { is_expected.to be nil }
    end

    context 'a digest' do
      let(:digest) { Datadog::Tracing::TraceDigest.new(trace_id: 0xC0FFEE, span_id: 0xBEE, **options) }
      let(:options) { {} }

      it { expect(traceparent).to eq('00-00000000000000000000000000c0ffee-0000000000000bee-00') }

      context 'with trace_distributed_id' do
        let(:options) { { trace_distributed_id: 0xACE00000000000000000000000C0FFEE } }
        it 'prioritizes the original trace_distributed_id' do
          expect(traceparent).to eq('00-ace00000000000000000000000c0ffee-0000000000000bee-00')
        end
      end

      context 'with trace_flags' do
        context 'with a dropped trace' do
          let(:options) { { trace_flags: 0xFF, trace_sampling_priority: -1 } }

          it 'changes last bit to 0' do
            expect(trace_flags).to eq('fe')
          end
        end

        context 'with a kept trace' do
          let(:options) { { trace_flags: 0xFE, trace_sampling_priority: 1 } }

          it 'changes last bit to 1' do
            expect(trace_flags).to eq('ff')
          end
        end

        context 'with no priority sampling' do
          let(:options) { { trace_flags: 0xFF, trace_sampling_priority: nil } }

          it 'does not change the last bit' do
            expect(trace_flags).to eq('ff')
          end
        end
      end

      context 'with sampling priority' do
        {
          -1 => '00',
          0 => '00',
          1 => '01',
          2 => '01',
        }.each do |sampling_priority, expected_trace_flags|
          context "with sampling_priority #{sampling_priority}" do
            let(:digest) do
              Datadog::Tracing::TraceDigest.new(
                trace_id: 0xC0FFEE,
                span_id: 0xBEE,
                trace_sampling_priority: sampling_priority
              )
            end

            it "sets trace-flags to #{expected_trace_flags}" do
              expect(trace_flags).to eq(expected_trace_flags)
            end

            it "sets tracestate to s:#{sampling_priority}" do
              expect(tracestate).to eq("dd=s:#{sampling_priority}")
            end
          end
        end

        context 'with origin' do
          let(:digest) do
            Datadog::Tracing::TraceDigest.new(
              trace_id: 0xC0FFEE,
              span_id: 0xBEE,
              trace_sampling_priority: 1,
              trace_origin: 'synthetics'
            )
          end

          it { expect(tracestate).to eq('dd=s:1;o:synthetics') }
        end
      end

      context 'with origin' do
        let(:digest) do
          Datadog::Tracing::TraceDigest.new(
            trace_id: 0xC0FFEE,
            span_id: 0xBEE,
            trace_origin: origin
          )
        end

        let(:origin) { 'synthetics' }

        it { expect(tracestate).to eq('dd=o:synthetics') }

        context 'with invalid characters' do
          [
            "\u0000", # First unicode character
            "\u0019", # Last lower invalid character
            ',',
            ';',
            '=',
            "\u007F", # First upper invalid character
            "\u{10FFFF}" # Last unicode character
          ].each do |character|
            context character.inspect do
              let(:origin) { character }

              it { expect(tracestate).to eq('dd=o:_') }
            end
          end
        end
      end

      context 'with trace_distributed_tags' do
        let(:digest) do
          Datadog::Tracing::TraceDigest.new(
            trace_id: 0xC0FFEE,
            span_id: 0xBEE,
            trace_distributed_tags: tags
          )
        end

        context 'nil' do
          let(:tags) { nil }
          it { expect(tracestate).to be_nil }
        end

        context '{}' do
          let(:tags) { {} }
          it { expect(tracestate).to be_nil }
        end

        context "{ 'key' => 'value' }" do
          let(:tags) { { 'key' => 'value' } }
          it { expect(tracestate).to eq('dd=t.key:value') }
        end

        context "{ '_dd.p.dm' => '-1' }" do
          let(:tags) { { '_dd.p.dm' => '-1' } }
          it { expect(tracestate).to eq('dd=t.dm:-1') }
        end

        context "{ 'key' => 'value=with=equals' }" do
          let(:tags) { { 'key' => 'value=with=equals' } }
          it { expect(tracestate).to eq('dd=t.key:value:with:equals') }
        end

        context 'too large' do
          let(:tags) { { 'k' => 'v' * 250 } } # 257 chars after it's formatted as "dd=t.#{key}:#{value}"

          it { expect(tracestate).to be_nil }
        end

        context 'with the maximum size' do
          let(:tags) { { 'k' => 'v' * 249 } } # 256 chars after it's formatted as "dd=t.#{key}:#{value}"

          it { expect(tracestate.size).to eq(256) }
        end

        context 'invalid key characters' do
          [
            "\u0000", # First unicode character
            ' ', # Last lower invalid character
            ',',
            '=',
            "\u007F", # First upper invalid character
            "\u{10FFFF}" # Last unicode character
          ].each do |character|
            context character.inspect do
              let(:tags) { { character => 'value' } }

              it { expect(tracestate).to eq('dd=t._:value') }
            end
          end
        end

        context 'invalid value characters' do
          [
            "\u0000", # First unicode character
            "\u001F", # Last lower invalid character
            ',',
            ':',
            ';',
            "\u007F", # First upper invalid character
            "\u{10FFFF}" # Last unicode character
          ].each do |character|
            context character.inspect do
              let(:tags) { { 'key' => character } }

              it { expect(tracestate).to eq('dd=t.key:_') }
            end
          end
        end
      end

      context 'with a upstream tracestate' do
        let(:options) { { trace_state: upstream_tracestate } }
        let(:upstream_tracestate) { 'other=vendor' }

        context 'without local Datadog-specific values' do
          it 'propagates unmodified tracestate' do
            expect(tracestate).to eq(upstream_tracestate)
          end

          context 'with upstream `dd=` values' do
            let(:upstream_tracestate) { 'dd=old_value,other=vendor,dd=oops_forgot_to_remove_this' }

            it 'propagates unmodified tracestate' do
              expect(tracestate).to eq(upstream_tracestate)
            end
          end
        end

        context 'with local Datadog-specific values' do
          let(:options) { super().merge(trace_origin: 'origin') }

          context 'and existing `dd=` tracestate values' do
            let(:upstream_tracestate) { 'dd=old_value,other=vendor,dd=oops_forgot_to_remove_this' }

            it 'removes existing `dd=` values, prepending new `dd=` value' do
              expect(tracestate).to eq('dd=o:origin,other=vendor')
            end
          end

          context 'and 32 upstream tracestate entries' do
            let(:upstream_tracestate) { Array.new(32) { |i| "other=vendor#{i}" }.join(',') }

            it 'removes 1 trailing value, prepending new `dd=` value' do
              expect(tracestate).to eq('dd=o:origin,' + Array.new(31) { |i| "other=vendor#{i}" }.join(','))
            end
          end

          context 'and unknown `dd=` tracestate values' do
            let(:options) { super().merge(trace_origin: 'origin', trace_state_unknown_fields: 'future=field;') }

            it 'joins known and unknown `dd=` fields' do
              expect(tracestate).to eq('dd=o:origin;future=field,other=vendor')
            end
          end
        end
      end
    end
  end

  describe '#extract' do
    subject(:extract) { datadog.extract(data) }
    let(:data) do
      { prepare_key['traceparent'] => traceparent,
        prepare_key['tracestate'] => tracestate }
    end
    let(:traceparent) { "#{version}-#{trace_id}-#{parent_id}-#{trace_flags}" }
    let(:version) { '00' }
    let(:trace_id) { '00000000000000000000000000c0ffee' }
    let(:parent_id) { '0000000000000bee' }
    let(:trace_flags) { '00' }
    let(:tracestate) { '' }

    let(:digest) { extract }

    context 'with traceparent fields with incorrect sizes' do
      context 'version with incorrect size' do
        let(:version) { '0' }
        it { is_expected.to be_nil }
      end

      context 'trace_id with incorrect size' do
        let(:trace_id) { 'c0ffee' }
        it { is_expected.to be_nil }
      end

      context 'parent_id with incorrect size' do
        let(:parent_id) { 'fee' }
        it { is_expected.to be_nil }
      end

      context 'trace flags with incorrect size' do
        let(:trace_flags) { '0' }
        it { is_expected.to be_nil }
      end

      context 'more fields than expected' do
        let(:traceparent) { '00-00000000000000000000000000c0ffee-0000000000000bee-01-FFFFF' }
        it { is_expected.to be_nil }
      end
    end

    context 'without data' do
      let(:data) { {} }
      it { is_expected.to be nil }
    end

    context 'with valid trace_id and parent_id' do
      it { expect(digest.trace_id).to eq(0xC0FFEE) }
      it { expect(digest.span_id).to eq(0xBEE) }
      it { expect(digest.trace_origin).to be nil }
      it { expect(digest.trace_sampling_priority).to eq(0) }

      context 'and trace_id larger than 64 bits' do
        let(:trace_id) { 'ace00000000000000000000000c0ffee' }

        it { expect(digest.trace_id).to eq(0xC0FFEE) }
        it { expect(digest.trace_distributed_id).to eq(0xACE00000000000000000000000C0FFEE) }
      end

      context 'with sampling priority' do
        [
          { sampled_flag: 0, priority: -1, expected_priority: -1 },
          { sampled_flag: 0, priority: 0, expected_priority: 0 },
          { sampled_flag: 0, priority: 1, expected_priority: 0 },
          { sampled_flag: 0, priority: 2, expected_priority: 0 },
          { sampled_flag: 0, priority: nil, expected_priority: 0 },
          { sampled_flag: 1, priority: nil, expected_priority: 1 },
          { sampled_flag: 1, priority: -1, expected_priority: 1 },
          { sampled_flag: 1, priority: 0, expected_priority: 1 },
          { sampled_flag: 1, priority: 1, expected_priority: 1 },
          { sampled_flag: 1, priority: 2, expected_priority: 2 },
        ].each do |args|
          sampled_flag = args[:sampled_flag]
          priority = args[:priority]
          expected_priority = args[:expected_priority]

          context "with sampled flag #{sampled_flag} and incoming sampling priority #{priority.inspect}" do
            let(:trace_flags) { "0#{sampled_flag}" }
            let(:tracestate) { "dd=s:#{priority}" }

            it "return sampling priority #{expected_priority}" do
              expect(digest.trace_sampling_priority).to eq(expected_priority)
            end
          end
        end
      end

      context 'with origin' do
        let(:tracestate) { 'dd=o:synthetics' }

        it { expect(digest.trace_origin).to eq('synthetics') }
      end

      context 'with trace_distributed_tags' do
        subject(:trace_distributed_tags) { extract.trace_distributed_tags }
        let(:tracestate) { "dd=#{tags}" }

        context 'nil' do
          let(:tags) { nil }
          it { is_expected.to be_nil }
        end

        context 'an empty value' do
          let(:tags) { '' }
          it { is_expected.to be_nil }
        end

        context "{ '_dd.p.key' => 'value' }" do
          let(:tags) { 't.key:value' }
          it { is_expected.to eq('_dd.p.key' => 'value') }
        end

        context "{ '_dd.p.dm' => '-1' }" do
          let(:tags) { 't.dm:-1' }
          it { is_expected.to eq('_dd.p.dm' => '-1') }
        end

        context "{ 'key' => 'value=with=equals' }" do
          let(:tags) { 't.key:value:with:equals' }
          it { is_expected.to eq('_dd.p.key' => 'value=with=equals') }
        end
      end

      context 'with unknown tracestate fields' do
        let(:tracestate) { "dd=i_don't_know_this:field;o:origin" }

        it { expect(digest.trace_state_unknown_fields).to eq("i_don't_know_this:field;") }

        it { expect(digest.trace_id).to eq(0xC0FFEE) }
        it { expect(digest.span_id).to eq(0xBEE) }
        it { expect(digest.trace_origin).to eq('origin') }
      end

      context 'with multiple tracestate vendors' do
        let(:tracestate) { 'dd=o:origin,v1=1,v2=2' }

        it { expect(digest.trace_id).to eq(0xC0FFEE) }
        it { expect(digest.span_id).to eq(0xBEE) }
        it { expect(digest.trace_state).to eq('v1=1,v2=2') }
        it { expect(digest.trace_origin).to eq('origin') }
      end

      context 'trailing whitespace' do
        let(:traceparent) { '00-00000000000000000000000000c0ffee-0000000000000bee-00 ' }

        it { expect(digest.trace_id).to eq(0xC0FFEE) }
        it { expect(digest.span_id).to eq(0xBEE) }
        it { expect(digest.trace_sampling_priority).to eq(0) }
      end

      context 'with a future version' do
        let(:version) { '57' }
        let(:trace_flags) { '01' }

        shared_examples 'parses tracestate using version 00 logic' do
          it { expect(digest.trace_id).to eq(0xC0FFEE) }
          it { expect(digest.span_id).to eq(0xBEE) }
          it { expect(digest.trace_sampling_priority).to eq(1) }
        end

        include_examples 'parses tracestate using version 00 logic'

        context 'traceparent ending in dash' do
          let(:traceparent) { super() + '-' }

          include_examples 'parses tracestate using version 00 logic'
        end

        context 'traceparent with extra unknown fields' do
          let(:traceparent) { super() + '-fff-aaa' }

          include_examples 'parses tracestate using version 00 logic'
        end
      end

      context 'with an invalid version' do
        let(:version) { 'ff' }
        it { is_expected.to be_nil }
      end
    end

    context 'with only trace_id' do
      let(:parent_id) { '0000000000000000' }
      it { is_expected.to be nil }
    end

    context 'with only parent_id' do
      let(:trace_id) { '00000000000000000000000000000000' }
      it { is_expected.to be nil }
    end
  end
end

RSpec.describe Datadog::Tracing::Distributed::TraceContext do
  it_behaves_like 'Trace Context distributed format'
end
