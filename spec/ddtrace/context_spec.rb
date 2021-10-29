# typed: false
require 'spec_helper'

require 'ddtrace'

RSpec.describe Datadog::Context do
  subject(:context) { described_class.new(**options) }

  let(:options) { {} }

  describe '#initialize' do
    context 'with defaults' do
      it do
        is_expected.to have_attributes(
          active_trace: nil
        )
      end
    end

    context 'given a trace' do
      # TODO
      it { is_expected.to_not be nil }
    end
  end
end
