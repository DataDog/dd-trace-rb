require "spec_helper"

require "datadog/core/utils/base64_codec"

RSpec.describe Datadog::Core::Utils::Base64Codec do
  describe ".encode64" do
    subject(:encoded) { described_class.encode64("hello") }

    it { is_expected.to eq("aGVsbG8=\n") }
  end

  describe ".strict_encode64" do
    subject(:encoded) { described_class.strict_encode64("hello") }

    it { is_expected.to eq("aGVsbG8=") }
  end

  describe ".strict_decode64" do
    subject(:decoded) { described_class.strict_decode64("aGVsbG8=") }

    it { is_expected.to eq("hello") }
  end
end
