require 'datadog/tracing/contrib/aws/services'

RSpec.describe Datadog::Tracing::Contrib::Aws do
  describe 'constant `SERVICES`' do
    subject(:services) { Datadog::Tracing::Contrib::Aws::SERVICES }

    it do
      expect(services).to be_frozen
    end

    it do
      expect(services.length).to eq(109)
    end

    it 'contains strings' do
      expect(services).to all(be_a String)
    end

    it 'contains frozen strings' do
      expect(services).to all(be_frozen)
    end
  end

  describe 'constant `SERVICE_HANDLERS`' do
    subject(:handlers) { Datadog::Tracing::Contrib::Aws::SERVICE_HANDLERS }

    it do
      expect(handlers.length).to eq(7)
    end

    it do
      expect(handlers.keys).to contain_exactly(
        'sqs',
        'sns',
        'dynamodb',
        'kinesis',
        'eventbridge',
        'states',
        's3'
      )
    end

    it do
      expect(handlers.values).to all(
        be_a Datadog::Tracing::Contrib::Aws::Service::Base
      )
    end
  end
end
