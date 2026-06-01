# frozen_string_literal: true

require 'spec_helper'
require 'datadog/appsec/route_normalizer'

RSpec.describe Datadog::AppSec::RouteNormalizer::Encoder do
  describe '.encode_static' do
    it { expect(described_class.encode_static('users')).to eq('users') }

    it { expect(described_class.encode_static('hello world')).to eq('hello%20world') }

    it { expect(described_class.encode_static('café')).to eq('caf%C3%A9') }

    it { expect(described_class.encode_static('/users/path')).to eq('/users/path') }

    it { expect(described_class.encode_static('a-b_c.d~e')).to eq('a-b_c.d~e') }

    it { expect(described_class.encode_static('a+b')).to eq('a%2Bb') }

    it { expect(described_class.encode_static('')).to eq('') }
  end
end
