require 'spec_helper'

require 'ddtrace'
require 'ddtrace/metrics'
require 'benchmark'

RSpec.describe Datadog::Metrics do
  subject(:test_object) { test_class.new }
  let(:test_class) { Class.new { include Datadog::Metrics } }

  it { is_expected.to have_attributes(statsd: nil) }
end
