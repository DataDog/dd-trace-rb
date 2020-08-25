require 'spec_helper'

require 'ddtrace/profiling/event'

RSpec.describe Datadog::Profiling::Event do
  subject(:event) { described_class.new }

  describe '::new' do
    it do
      is_expected.to have_attributes(
        timestamp: kind_of(Integer)
      )
    end
  end
end
