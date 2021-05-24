require 'ddtrace/contrib/support/spec_helper'
require 'ddtrace/ext/integration'

require 'cucumber'
require 'ddtrace'

require 'datadog/ci/contrib/support/spec_helper'

RSpec.describe 'Cucumber formatter' do
  extend ConfigurationHelpers

  include_context 'CI mode activated'

  let(:configuration_options) { {} }
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

  before do
    Datadog.configure do |c|
      c.use :cucumber, configuration_options
    end
  end

  context 'executing a test suite' do
    let(:args) { ['spec/datadog/ci/contrib/cucumber/cucumber.features'] }

    def do_execute
      cli.execute!(existing_runtime)
    end

    it 'creates spans for each scenario and step' do
      expect(kernel).to receive(:exit).with(0)

      do_execute

      scenario_span = spans.find { |s| s.resource == 'cucumber scenario' }
      step_span = spans.find { |s| s.resource == 'datadog' }

      expect(scenario_span.resource).to eq('cucumber scenario')
      expect(scenario_span.service).to eq(Datadog::CI::Contrib::Cucumber::Ext::SERVICE_NAME)
      expect(scenario_span.span_type).to eq(Datadog::CI::Ext::AppTypes::TEST)
      expect(scenario_span.name).to eq(Datadog::CI::Contrib::Cucumber::Ext::OPERATION_NAME)
      expect(step_span.resource).to eq('datadog')

      spans.each do |span|
        expect(span.get_tag(Datadog::Ext::DistributedTracing::ORIGIN_KEY))
          .to eq(Datadog::CI::Ext::Test::CONTEXT_ORIGIN)
      end
    end
  end
end
