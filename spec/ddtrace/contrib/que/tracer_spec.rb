require 'ddtrace/contrib/support/spec_helper'
require 'ddtrace/contrib/analytics_examples'
require 'ddtrace'
require 'que'

RSpec.describe Datadog::Contrib::Que::Tracer do
  let(:que_tracer) { described_class.new }

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
    context 'with default options' do
      let(:configuration_options) { {} }

      it 'captures spans for args and error counts' do
        args = { a: 1 }
        TestJobClass.run(args)

        expect(span.get_tag(Datadog::Contrib::Que::Ext::TAG_JOB_ARGS)).to eq(nil)
        expect(span.get_tag(Datadog::Contrib::Que::Ext::TAG_JOB_DATA)).to eq(nil)
      end
    end

    context 'with tag_args enabled' do
      let(:configuration_options) { {tag_args: true} }

      it 'captures spans for args and error counts' do
        args = { a: 1 }
        TestJobClass.run(args)

        expect(span.get_tag(Datadog::Contrib::Que::Ext::TAG_JOB_ARGS)).to eq([args].to_s)
      end
    end
  end
end
