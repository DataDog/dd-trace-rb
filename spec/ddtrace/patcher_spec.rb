require 'spec_helper'

require 'ddtrace'

RSpec.describe Datadog::Patcher do
  describe '.without_warnings' do
    it { expect { |b| described_class.without_warnings(&b) }.to yield_control }
  end
end
