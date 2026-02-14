# frozen_string_literal: true

RSpec.shared_context 'Active Storage configuration' do
  before do
    config = double('config')
    allow(config).to receive(:[]).with(:service_name).and_return(nil)
    allow(config).to receive(:[]).with(:analytics_enabled).and_return(false)
    allow(config).to receive(:[]).with(:analytics_sample_rate).and_return(1.0)
    allow(Datadog.configuration.tracing).to receive(:[]).with(:active_storage).and_return(config)
  end
end
