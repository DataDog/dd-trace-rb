require "datadog/di/spec_helper"
require 'datadog/di/transport/http'

RSpec.describe Datadog::DI::Transport::Input::Transport do
  di_test

  let(:transport) do
    Datadog::DI::Transport::HTTP.input(agent_settings: agent_settings, logger: logger)
  end

  let(:agent_settings) { Datadog::Core::Configuration::AgentSettingsResolver.call(settings, logger: nil) }

  let(:settings) do
    Datadog::Core::Configuration::Settings.new
  end

  let(:logger) do
    instance_double(Logger).tap do |l|
      allow(l).to receive(:debug)
    end
  end

  let(:tags) { [] }

  context 'when snapshot contains binary data converted to Python repr' do
    context 'with all 256 byte values' do
      # Create a string containing all possible byte values (0x00-0xFF)
      # This simulates capturing a binary buffer in dynamic instrumentation
      let(:binary_string) do
        (0..255).map { |i| i.chr(Encoding::BINARY) }.join.force_encoding(Encoding::BINARY)
      end

      # Simulate what the serializer produces after converting to Python repr
      let(:python_repr) do
        result = +"b'"
        binary_string.each_byte do |byte|
          case byte
          when 0x09 then result << '\\t'
          when 0x0A then result << '\\n'
          when 0x0D then result << '\\r'
          when 0x27 then result << "\\'"
          when 0x5C then result << '\\\\'
          when 0x20..0x7E then result << byte.chr
          else result << format('\\x%02x', byte)
          end
        end
        result << "'"
        result.force_encoding(Encoding::UTF_8)
      end

      let(:snapshot) do
        {
          'id' => 'test-snapshot',
          'timestamp' => Time.now.to_i,
          'captures' => {
            'locals' => {
              'binary_data' => python_repr
            }
          }
        }
      end

      it 'has all 256 unique bytes in original' do
        expect(binary_string.bytes.uniq.sort).to eq((0..255).to_a)
        expect(binary_string.encoding).to eq(Encoding::BINARY)
      end

      it 'successfully serializes Python repr through transport layer' do
        # Python repr format is JSON-safe
        expect {
          transport.send_input([snapshot], tags)
        }.not_to raise_error
      end

      it 'produces valid JSON' do
        json_output = JSON.dump(snapshot)
        expect(json_output).to be_a(String)
        expect(json_output.encoding).to eq(Encoding::UTF_8)

        # Can round-trip through JSON
        parsed = JSON.parse(json_output)
        expect(parsed['captures']['locals']['binary_data']).to eq(python_repr)
      end
    end

    context 'with binary string that is invalid UTF-8' do
      # Create a string with bytes that are invalid UTF-8 sequences
      let(:binary_string) { "\x80\x81\x82\xFF\xFE".b }

      # After conversion to Python repr
      let(:python_repr) { "b'\\x80\\x81\\x82\\xff\\xfe'" }

      let(:snapshot) do
        {
          'id' => 'test-snapshot',
          'captures' => {
            'locals' => {
              'binary_data' => python_repr
            }
          }
        }
      end

      before do
        # Assert the original is indeed invalid UTF-8
        utf8_attempt = binary_string.dup.force_encoding(Encoding::UTF_8)
        expect(utf8_attempt.valid_encoding?).to be false
      end

      it 'successfully serializes Python repr of binary string' do
        expect {
          transport.send_input([snapshot], tags)
        }.not_to raise_error
      end

      it 'Python repr is valid UTF-8' do
        expect(python_repr.encoding).to eq(Encoding::UTF_8)
        expect(python_repr.valid_encoding?).to be true
      end
    end
  end

  context 'when the combined size of snapshots serialized exceeds intake max' do
    before do
      # Reduce limits to make the test run faster and not require a lot of memory
      stub_const('Datadog::DI::Transport::Input::Transport::DEFAULT_CHUNK_SIZE', 100_000)
      stub_const('Datadog::DI::Transport::Input::Transport::MAX_CHUNK_SIZE', 200_000)
    end

    let(:snapshot) do
      # It doesn't matter what the payload is, generate a fake one here.
      # This payload serializes to 9781 bytes of JSON.
      1000.times.map do |i|
        [i, i]
      end.to_h
    end

    let(:snapshots) do
      # This serializes to 978201 bytes of JSON - just under 1 MB.
      [snapshot] * 100
    end

    it 'chunks snapshots' do
      # Just under 1 MB payload, default chunk size ~100 KB, we expect 10 chunks
      expect(transport).to receive(:send_input_chunk).exactly(10).times do |chunked_payload, serialized_tags|
        expect(chunked_payload.length).to be < 100_000
        expect(chunked_payload.length).to be > 90_000
      end
      transport.send_input(snapshots, tags)
    end

    context 'when individual snapshot exceeds intake max' do
      before do
        # Reduce limits even more to force a reasonably-sized snapshot to be dropped
        stub_const('Datadog::DI::Transport::Input::Transport::MAX_SERIALIZED_SNAPSHOT_SIZE', 2_000)
      end

      let(:small_snapshot) do
        20.times.map do |i|
          [i, i]
        end.to_h
      end

      let(:snapshots) do
        [small_snapshot, snapshot]
      end

      it 'drops snapshot that is too big' do
        expect(transport).to receive(:send_input_chunk).once do |chunked_payload, serialized_tags|
          expect(chunked_payload.length).to be < 1_000
          expect(chunked_payload.length).to be > 100
        end
        expect_lazy_log(logger, :debug, 'di: dropping too big snapshot')
        transport.send_input(snapshots, tags)
      end
    end
  end
end
