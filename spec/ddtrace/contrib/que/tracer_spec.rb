require 'ddtrace/contrib/support/spec_helper'
require 'ddtrace/contrib/analytics_examples'
require 'ddtrace'
require 'que'

RSpec.describe Datadog::Contrib::Que::Tracer do
  let(:que_tracer) { described_class.new }
  let(:configuration_options) { {} }

  class TestJobClass < ::Que::Job
    def run(*args); end
  end

  before do
    Datadog.configure do |c|
      c.use :que, configuration_options
    end
  end

  around do |example|
    Datadog.registry[:que].reset_configuration!
    example.run
    Datadog.registry[:que].reset_configuration!
  end

  describe '#call' do
    context 'with minimal arguments' do
      it 'captures spans for args and error counts' do
        args = { a: 1, b: 2 }
        TestJobClass.run(args)

        expect(span.get_tag(Datadog::Contrib::Que::Ext::TAG_JOB_ARGS)).to eq([args].to_s)
        expect(span.get_tag(Datadog::Contrib::Que::Ext::TAG_JOB_ERROR_COUNT)).to eq(0.0)
      end
    end
  end
end
