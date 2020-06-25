require 'ddtrace/contrib/support/spec_helper'

require 'ddtrace/contrib/configuration/resolver'

RSpec.describe Datadog::Contrib::Configuration::Resolver do
  subject(:resolver) { described_class.new(&default_config_block) }
  let(:default_config_block) { proc { config_class.new } }
  let(:config_class) { Class.new }

  describe '#resolve' do
    subject(:resolve) { resolver.resolve(key) }
    let(:key) { double('key') }
    it { is_expected.to be key }
  end

  describe '#add' do
    subject(:add) { resolver.add(key) }
    let(:key) { double('key') }
    it { is_expected.to be key }
  end
end
