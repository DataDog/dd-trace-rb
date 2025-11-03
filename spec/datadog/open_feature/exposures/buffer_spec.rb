# frozen_string_literal: true

require 'spec_helper'
require 'datadog/open_feature/exposures'

RSpec.describe Datadog::OpenFeature::Exposures::Buffer do
  subject(:buffer) { described_class.new(1) }

  describe '#drain' do
    it do
      buffer.push(:first)
      buffer.push(:second)

      drained, dropped = buffer.drain!

      expect(drained.length).to eq(1)
      expect(dropped).to eq(1)
    end
  end
end

