require 'spec_helper'

require 'datadog/tracing/distributed/datadog'
require 'datadog/tracing/trace_digest'
require 'datadog/tracing/utils'

RSpec.shared_examples 'Baggage distributed format' do
  let(:propagation_style_inject) { %w[baggage] }
  let(:propagation_style_extract) { %w[baggage] }

  let(:prepare_key) { defined?(super) ? super() : proc { |key| key } }

  let(:max_baggage_items) { 64 }
  let(:max_baggage_bytes) { 8192 }

  describe '#inject!' do
    subject(:inject!) { propagation.inject!(digest, data) }
    let(:data) { {} }

    context 'with nil digest' do
      let(:digest) { nil }
      it { is_expected.to be nil }
    end

    context 'with TraceDigest' do
      let(:digest) do
        Datadog::Tracing::TraceDigest.new(
          baggage: {'key' => 'value'},
        )
      end

      it do
        inject!
        expect(data).to eq(
          'baggage' => 'key=value',
        )
      end

      context 'with multiple key value' do
        let(:digest) do
          Datadog::Tracing::TraceDigest.new(
            baggage: {'key' => 'value', 'key2' => 'value2'},
          )
        end

        it do
          inject!
          expect(data).to eq(
            'baggage' => 'key=value,key2=value2',
          )
        end
      end

      context 'with special allowed characters' do
        let(:digest) do
          Datadog::Tracing::TraceDigest.new(
            baggage: {'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!#$&\'*+-.^_`|~' =>
            'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!#$&\'()*+-./:<>?@[]^_`{|}~',
                      'key2' => 'value2'},
          )
        end

        it do
          inject!
          expect(data).to eq(
            'baggage' => 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!#$&\'*+-.^' \
            '_`|~=ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!#$&\'()*+-./:<>?@[]^_`{|}~,key2=value2',
          )
        end
      end

      context 'with special disallowed characters' do
        let(:digest) do
          Datadog::Tracing::TraceDigest.new(
            baggage: {'key with=spacesand%' => 'value with=spaces'},
          )
        end

        it do
          inject!
          expect(data).to eq(
            'baggage' => 'key%20with%3Dspacesand%25=value%20with%3Dspaces',
          )
        end
      end

      context 'with other special disallowed characters' do
        let(:digest) do
          Datadog::Tracing::TraceDigest.new(
            baggage: {'userId' => 'Amélie'},
          )
        end

        it do
          inject!
          expect(data).to eq(
            'baggage' => 'userId=Am%C3%A9lie',
          )
        end
      end

      context 'when baggage size exceeds maximum items' do
        let(:digest) do
          Datadog::Tracing::TraceDigest.new(baggage: (1..(max_baggage_items + 1)).map { |i| ["key#{i}", "value#{i}"] }.to_h)
        end

        it 'logs a warning and stops injecting excess items' do
          expect(Datadog.logger).to receive(:warn).with('Baggage item limit (64) exceeded, dropping excess items')
          inject!
          expect(data['baggage'].split(',').size).to eq(max_baggage_items)
        end
      end

      context 'when baggage size exceeds maximum bytes' do
        let(:digest) do
          Datadog::Tracing::TraceDigest.new(baggage: {'key1' => 'value1', 'key' => 'a' * (max_baggage_bytes + 1)})
        end

        it 'logs a warning and stops injecting excess items' do
          expect(Datadog.logger).to receive(:warn).with('Baggage header size (8192) exceeded, dropping excess items')
          inject!
          expect(data['baggage']).to eq('key1=value1')
        end
      end
    end
  end

  describe '#extract' do
    subject(:extract) { propagation.extract(data) }
    let(:digest) { extract }

    let(:data) { {} }

    context 'with empty data' do
      it { is_expected.to be nil }
    end

    context 'single key value' do
      let(:data) do
        {prepare_key['baggage'] => 'key=value'}
      end

      it { expect(digest.baggage).to eq({'key' => 'value'}) }
    end

    context 'multiple key value' do
      let(:data) do
        {prepare_key['baggage'] => 'key=value,key2=value2'}
      end

      it { expect(digest.baggage).to eq({'key' => 'value', 'key2' => 'value2'}) }
    end

    context 'with special allowed characters' do
      let(:data) do
        {prepare_key['baggage'] => '&\'*`|~=$&\'()*,key2=value2'}
      end

      it {
        expect(digest.baggage).to eq({'&\'*`|~' => '$&\'()*', 'key2' => 'value2'})
      }
    end

    context 'with special disallowed characters and trimming whitespace on ends' do
      let(:data) do
        {prepare_key['baggage'] => ' key%20with%3Dspacesand%25 = value%20with%3Dspaces , key2=value2'}
      end

      it { expect(digest.baggage).to eq({'key with=spacesand%' => 'value with=spaces', 'key2' => 'value2'}) }
    end
  end
end

RSpec.describe Datadog::Tracing::Distributed::Baggage do
  subject(:propagation) { described_class.new(fetcher: fetcher_class) }
  let(:fetcher_class) { Datadog::Tracing::Distributed::Fetcher }

  let(:max_baggage_items) { 64 }
  let(:max_baggage_bytes) { 8192 }

  it_behaves_like 'Baggage distributed format'

  describe 'baggage tag conversion' do
    subject(:extract) { propagation.extract(data) }
    let(:trace_digest) { extract }
    let(:prepare_key) { proc { |key| key } }

    before do
      # Mock the baggage_tag_keys configuration
      allow(propagation).to receive(:instance_variable_get).with(:@baggage_tag_keys).and_return(baggage_tag_keys)
      propagation.instance_variable_set(:@baggage_tag_keys, baggage_tag_keys)
    end

    context 'Default Behavior with no configuration set' do
      let(:data) do
        {prepare_key['baggage'] => 'user.id=12345,correlation_id=abc-xyz-999,session.id=test123'}
      end
      let(:baggage_tag_keys) { ['user.id', 'session.id', 'account.id'] }

      it 'only adds configured keys as trace distributed tags' do
        # Only user.id and session.id should be added (matches default config and present in baggage)
        expect(trace_digest.trace_distributed_tags['baggage.user.id']).to eq('12345')
        expect(trace_digest.trace_distributed_tags['baggage.session.id']).to eq('test123')
        # These should not be added (not in default config)
        expect(trace_digest.trace_distributed_tags['baggage.correlation_id']).to be_nil
        # account.id is in config but not in baggage
        expect(trace_digest.trace_distributed_tags['baggage.account.id']).to be_nil
      end
    end

    context 'Specifying Keys in configuration' do
      let(:data) do
        {prepare_key['baggage'] => 'user.id=99999,session_id=mysession,feature_flag=beta'}
      end
      let(:baggage_tag_keys) { ['session_id', 'feature_flag'] }

      it 'only adds specified keys as trace distributed tags' do
        # Only configured keys should be added
        expect(trace_digest.trace_distributed_tags['baggage.session_id']).to eq('mysession')
        expect(trace_digest.trace_distributed_tags['baggage.feature_flag']).to eq('beta')
        # This should not be added (not in config)
        expect(trace_digest.trace_distributed_tags['baggage.user.id']).to be_nil
      end
    end

    context 'Disabled Baggage Tags in configuration' do
      let(:data) do
        {prepare_key['baggage'] => 'user.id=BaggageValue,session.id=mysession'}
      end
      let(:baggage_tag_keys) { [] } # Empty array means disabled

      it 'does not add any baggage tags when disabled' do
        # No baggage tags should be added when disabled
        expect(trace_digest.trace_distributed_tags['baggage.user.id']).to be_nil
        expect(trace_digest.trace_distributed_tags['baggage.session.id']).to be_nil
      end
    end

    context 'Malformed Baggage Headers (empty values)' do
      let(:data) do
        {prepare_key['baggage'] => 'user.id='}
      end
      let(:baggage_tag_keys) { ['user.id', 'session.id', 'account.id'] }

      it 'does not add trace distributed tags for empty baggage values' do
        # Empty values should not be added as trace distributed tags
        expect(trace_digest.trace_distributed_tags['baggage.user.id']).to be_nil
      end
    end

    context 'Wildcard configuration (*) includes all baggage keys' do
      let(:data) do
        {prepare_key['baggage'] => 'user.id=12345,custom.key=custom_value,another.key=another_value'}
      end
      let(:baggage_tag_keys) { ['*'] } # Wildcard means all keys

      it 'adds all baggage keys as trace distributed tags' do
        # All baggage keys should be added with wildcard config
        expect(trace_digest.trace_distributed_tags['baggage.user.id']).to eq('12345')
        expect(trace_digest.trace_distributed_tags['baggage.custom.key']).to eq('custom_value')
        expect(trace_digest.trace_distributed_tags['baggage.another.key']).to eq('another_value')
      end
    end
  end

  describe 'telemetry integration' do
    let(:telemetry) { instance_double(Datadog::Core::Telemetry::Component) }

    before do
      # Mock the telemetry component and tracer (needed by test helpers)
      tracer = instance_double(Datadog::Tracing::Tracer)
      allow(Datadog).to receive(:send).with(:components).and_return(
        double(telemetry: telemetry, tracer: tracer)
      )
    end

    describe '#inject! telemetry' do
      let(:data) { {} }

      context 'successful injection' do
        let(:digest) do
          Datadog::Tracing::TraceDigest.new(
            baggage: {'key' => 'value'}
          )
        end

        it 'records successful injection telemetry' do
          expect(telemetry).to receive(:inc).with(
            'instrumentation_telemetry_data.tracers',
            'context_header_style.injected',
            1,
            tags: {'header_style' => 'baggage'}
          )

          propagation.inject!(digest, data)
        end
      end

      context 'when baggage item count exceeds limit' do
        let(:digest) do
          baggage = {}
          70.times { |i| baggage["key#{i}"] = "value#{i}" }
          Datadog::Tracing::TraceDigest.new(baggage: baggage)
        end

        it 'records item count truncation telemetry' do
          expect(telemetry).to receive(:inc).with(
            'instrumentation_telemetry_data.tracers',
            'context_header.truncated',
            1,
            tags: {'header_style' => 'baggage', 'truncation_reason' => 'baggage_item_count_exceeded'}
          )
          expect(telemetry).to receive(:inc).with(
            'instrumentation_telemetry_data.tracers',
            'context_header_style.injected',
            1,
            tags: {'header_style' => 'baggage'}
          )

          propagation.inject!(digest, data)
        end
      end

      context 'when baggage header size exceeds limit' do
        let(:digest) do
          # Create baggage items that will exceed the byte limit
          large_value = 'x' * 200
          baggage = {}
          50.times { |i| baggage["key#{i}"] = large_value }
          Datadog::Tracing::TraceDigest.new(baggage: baggage)
        end

        it 'records byte count truncation telemetry' do
          expect(telemetry).to receive(:inc).with(
            'instrumentation_telemetry_data.tracers',
            'context_header.truncated',
            1,
            tags: {'header_style' => 'baggage', 'truncation_reason' => 'baggage_byte_count_exceeded'}
          )
          expect(telemetry).to receive(:inc).with(
            'instrumentation_telemetry_data.tracers',
            'context_header_style.injected',
            1,
            tags: {'header_style' => 'baggage'}
          )

          propagation.inject!(digest, data)
        end
      end

      context 'with nil digest' do
        let(:digest) { nil }

        it 'does not record any telemetry' do
          expect(telemetry).not_to receive(:inc)

          propagation.inject!(digest, data)
        end
      end

      context 'with empty baggage' do
        let(:digest) do
          Datadog::Tracing::TraceDigest.new(baggage: {})
        end

        it 'does not record any telemetry' do
          expect(telemetry).not_to receive(:inc)

          propagation.inject!(digest, data)
        end
      end
    end

    describe '#extract telemetry' do
      context 'successful extraction' do
        let(:data) { {'baggage' => 'key=value'} }

        it 'records successful extraction telemetry' do
          expect(telemetry).to receive(:inc).with(
            'instrumentation_telemetry_data.tracers',
            'context_header_style.extracted',
            1,
            tags: {'header_style' => 'baggage'}
          )

          propagation.extract(data)
        end
      end

      context 'malformed baggage - missing value' do
        let(:data) { {'baggage' => 'key='} }

        it 'records malformed header telemetry' do
          expect(telemetry).to receive(:inc).with(
            'instrumentation_telemetry_data.tracers',
            'context_header_style.malformed',
            1,
            tags: {'header_style' => 'baggage'}
          )

          result = propagation.extract(data)
          expect(result).to be_a(Datadog::Tracing::TraceDigest)
          expect(result.baggage).to eq({})
        end
      end

      context 'with an empty list member' do
        let(:data) { {'baggage' => 'key=value,'} }

        it 'skips the empty item' do
          expect(telemetry).to receive(:inc).with(
            'instrumentation_telemetry_data.tracers',
            'context_header_style.extracted',
            1,
            tags: {'header_style' => 'baggage'}
          )

          result = propagation.extract(data)

          expect(result).to be_a(Datadog::Tracing::TraceDigest)
          expect(result.baggage).to eq('key' => 'value')
        end
      end

      context 'when baggage item count exceeds limit' do
        let(:data) do
          {'baggage' => (1..(max_baggage_items + 2)).map { |i| "key#{i}=value#{i}" }.join(',')}
        end

        before { allow(telemetry).to receive(:inc) }

        it 'extracts baggage up to the item limit' do
          baggage = propagation.extract(data).baggage

          expect(baggage).to have(max_baggage_items).items
          expect(baggage).to include('key64' => 'value64')

          expect(baggage).not_to include('key65')
        end

        it 'records item count truncation telemetry' do
          expect(telemetry).to receive(:inc).with(
            'instrumentation_telemetry_data.tracers',
            'context_header.truncated',
            1,
            tags: {'header_style' => 'baggage', 'truncation_reason' => 'baggage_item_count_exceeded'}
          )
          expect(telemetry).to receive(:inc).with(
            'instrumentation_telemetry_data.tracers',
            'context_header_style.extracted',
            1,
            tags: {'header_style' => 'baggage'}
          )

          propagation.extract(data)
        end

        context 'with duplicate baggage keys' do
          let(:data) do
            {'baggage' => (1..(max_baggage_items + 2)).map { |i| "same_key=value#{i}" }.join(',')}
          end

          it 'limits extraction by headers ingested, not stored' do
            expect(telemetry).to receive(:inc).with(
              'instrumentation_telemetry_data.tracers',
              'context_header.truncated',
              1,
              tags: {'header_style' => 'baggage', 'truncation_reason' => 'baggage_item_count_exceeded'}
            )

            expect(propagation.extract(data).baggage).to eq("same_key" => "value64"), "Keeps the last entry"
          end
        end
      end

      context 'when baggage header size exceeds limit' do
        before { allow(telemetry).to receive(:inc) }

        context 'with a single item that is too large' do
          let(:key) { 'key=' }
          let(:value) { 'a' * (max_baggage_bytes - key.bytesize + 1) }
          let(:data) { {'baggage' => "#{key}#{value}"} }

          it 'extracts empty baggage' do
            result = propagation.extract(data)
            expect(result).to be_a(Datadog::Tracing::TraceDigest)
            expect(result.baggage).to eq({})
          end

          it 'records byte count truncation telemetry' do
            expect(telemetry).to receive(:inc).with(
              'instrumentation_telemetry_data.tracers',
              'context_header.truncated',
              1,
              tags: {'header_style' => 'baggage', 'truncation_reason' => 'baggage_byte_count_exceeded'}
            )

            propagation.extract(data)
          end
        end

        context 'with a complete entry before the byte limit' do
          let(:data) do
            {
              'baggage' => "key1=#{'a' * (max_baggage_bytes / 2)},key2=#{'b' * (max_baggage_bytes / 2)}"
            }
          end

          it 'extracts complete entry only' do
            result = propagation.extract(data)

            expect(result.baggage.keys).to contain_exactly('key1')
          end
        end

        context 'with a trailing entry truncated inside a multibyte character' do
          let(:complete_entry) { 'key1=value1' }
          let(:partial_key) { 'key2=' }
          let(:partial_value) do
            'a' * (max_baggage_bytes - complete_entry.bytesize - 1 - partial_key.bytesize - 1) + '🍀' # A 4-leaf clover, 4-byte character
          end
          let(:data) { {'baggage' => "#{complete_entry},#{partial_key}#{partial_value}"} }

          it 'extracts complete entries before the partial multibyte tail' do
            result = propagation.extract(data)

            expect(result.baggage).to eq('key1' => 'value1')
          end
        end

        context 'when a complete entry fits exactly the byte limit' do
          let(:key) { 'key1=' }
          let(:value) { 'a' * (max_baggage_bytes - key.bytesize) }
          let(:data) { {'baggage' => "#{key}#{value},next=value"} }

          it 'extracts complete entry' do
            result = propagation.extract(data)

            expect(result.baggage.keys).to contain_exactly('key1')
          end

          context 'with spec-allowed whitespace before the next separator' do
            let(:data) { {'baggage' => "#{key}#{value} ,next=value"} }

            it 'drops entry to avoid unbounded whitespace parsing beyond byte limit' do
              result = propagation.extract(data)

              expect(result.baggage).to eq({})
            end
          end
        end
      end
    end
  end
end
