require 'spec_helper'

require 'ddtrace'

RSpec.describe Datadog::Contrib::Configuration::Resolver do
  subject(:resolver) { described_class.new }

  describe '#resolve' do
    subject(:resolve) { resolver.resolve(name) }
    let(:name) { double('name') }
    it { is_expected.to be name }
  end
end
