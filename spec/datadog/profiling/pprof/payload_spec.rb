require 'spec_helper'

require 'datadog/profiling/pprof/payload'

RSpec.describe Datadog::Profiling::Pprof::Payload do
  subject(:payload) { described_class.new(data, types) }

  let(:data) { double('data') }
  let(:types) { [] }

  describe '::new' do
    it do
      is_expected.to have_attributes(
        data: data,
        types: types
      )
    end
  end

  describe '#to_s' do
    subject(:to_ess) { payload.to_s }

    it { is_expected.to be(data) }
  end
end
