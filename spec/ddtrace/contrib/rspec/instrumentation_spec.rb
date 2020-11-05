require 'ddtrace/contrib/support/spec_helper'
require 'ddtrace/contrib/analytics_examples'
require 'ddtrace/ext/integration'

require 'rspec'
require 'ddtrace'

RSpec.describe 'RSpec hooks' do
  extend ConfigurationHelpers

  let(:configuration_options) { {} }

  around do |example|
    # Datadog.configuration.reset!

    old_configuration = ::RSpec.configuration
    ::RSpec.configuration = ::RSpec::Core::Configuration.new

    Datadog.configure do |c|
      c.use :rspec, configuration_options
    end
    example.run

    RSpec.configuration = old_configuration
    Datadog.configuration.reset!
  end

  context 'executing a test suite' do
    it 'creates spans for each example' do
      examples = {}
      group = RSpec.describe 'group' do
        it 'foo' do
          examples['foo'] = Datadog.configuration[:rspec][:tracer].active_span
          expect(1).to eq(1)
        end

        it 'bar' do
          examples['bar'] = Datadog.configuration[:rspec][:tracer].active_span
          expect(1).to eq(2)
        end
      end

      group.run

      expect(examples.count).to eq(2)
      expect(spans.count).to eq(3)

      group_span = spans.find { |s| s.resource == 'group' }
      foo_span = examples['foo']
      bar_span = examples['bar']

      expect(group_span.service).to eq(Datadog::Contrib::RSpec::Ext::SERVICE_NAME)
      expect(group_span.span_type).to eq(Datadog::Ext::AppTypes::TEST)
      expect(group_span.name).to eq(Datadog::Contrib::RSpec::Ext::EXAMPLE_GROUP_OPERATION_NAME)
      expect(foo_span.span_type).to eq(Datadog::Ext::AppTypes::TEST)
      expect(foo_span.name).to eq(Datadog::Contrib::RSpec::Ext::OPERATION_NAME)
      expect(bar_span.span_type).to eq(Datadog::Ext::AppTypes::TEST)
      expect(bar_span.name).to eq(Datadog::Contrib::RSpec::Ext::OPERATION_NAME)
    end
  end
end
