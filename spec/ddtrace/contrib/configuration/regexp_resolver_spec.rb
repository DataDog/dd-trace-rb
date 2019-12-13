require 'spec_helper'
require 'ddtrace'

RSpec.describe Datadog::Contrib::Configuration::Resolvers::RegexpResolver do
  subject(:resolver) { described_class.new }

  describe '#resolve' do
    subject(:resolve) { resolver.resolve(name) }

    context 'when the key is already added' do
      let(:name) { double('name') }
      before do
        resolver.add_key(/name/)
      end

      it do
        is_expected.to eq(/name/)
      end
    end

    context 'when the pattern is not found' do
      let(:name) { 'not_found' }

      it do
        is_expected.to be :default
      end
    end
  end
end
