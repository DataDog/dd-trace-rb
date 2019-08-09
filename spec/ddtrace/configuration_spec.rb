require 'spec_helper'

require 'ddtrace/patcher'
require 'ddtrace/configuration'

RSpec.describe Datadog::Configuration do
  context 'when extended by a class' do
    subject(:test_class) { stub_const('TestClass', Class.new { extend Datadog::Configuration }) }

    describe '#configure' do
      subject(:configure) { test_class.configure }
    end
  end
end
