require 'ddtrace/contrib/support/spec_helper'
require 'ddtrace/contrib/analytics_examples'
require 'ddtrace/ext/integration'

require 'cucumber'
require 'ddtrace'

RSpec.describe 'Cucumber formatter' do
  extend ConfigurationHelpers

  let(:configuration_options) { {} }

  before(:each) do
    Datadog.configure do |c|
      c.use :cucumber, configuration_options
    end
  end

  # Cucumber runtime setup
  let(:existing_runtime) { Cucumber::Runtime.new(runtime_options) }
  let(:runtime_options)  { {} }

  # CLI configuration
  let(:args)   { [] }
  let(:stdin)  { StringIO.new }
  let(:stdout) { StringIO.new }
  let(:stderr) { StringIO.new }
  let(:kernel) { double(:kernel) }
  let(:cli)    { Cucumber::Cli::Main.new(args, stdin, stdout, stderr, kernel) }

  context 'executing a test suite' do
    let(:args) { ['spec/ddtrace/contrib/cucumber/cucumber.features'] }

    def do_execute
      cli.execute!(existing_runtime)
    end

    it 'creates spans for each scenario and step' do
      expect(kernel).to receive(:exit).with(0)

      do_execute

      expect(spans.length).to eq(2)
      expect(spans[1].resource).to eq('cucumber scenario')
      expect(spans[1].service).to eq(Datadog::Contrib::Cucumber::Ext::SERVICE_NAME)
      expect(spans[1].span_type).to eq(Datadog::Ext::AppTypes::TEST)
      expect(spans[0].resource).to eq('datadog')
    end
  end
end
