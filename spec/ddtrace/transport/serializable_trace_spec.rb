# typed: false
require 'spec_helper'

require 'ddtrace/transport/serializable_trace'

# rubocop:disable RSpec/EmptyExampleGroup
RSpec.describe Datadog::Transport::SerializableTrace do
  # TODO: Enable these tests
  # describe '#to_msgpack' do
  #   subject(:to_msgpack) { MessagePack.unpack(MessagePack.pack(span)) }

  #   it 'correctly performs a serialization round-trip' do
  #     is_expected.to eq(Hash[span.to_hash.map { |k, v| [k.to_s, v] }])
  #   end
  # end

  # describe '#to_json' do
  #   subject(:to_json) { JSON(JSON.dump(span)) }

  #   it 'correctly performs a serialization round-trip' do
  #     is_expected.to eq(Hash[span.to_hash.map { |k, v| [k.to_s, v] }])
  #   end
  # end
end
# rubocop:enable RSpec/EmptyExampleGroup
