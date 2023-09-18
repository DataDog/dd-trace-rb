require 'datadog/tracing/contrib/active_record/configuration/settings'
require 'datadog/tracing/contrib/service_name_settings_examples'

RSpec.describe Datadog::Tracing::Contrib::ActiveRecord::Configuration::Settings do
  it_behaves_like 'service name setting', 'mysql2' do
    before do
      allow(Datadog::Tracing::Contrib::ActiveRecord::Utils).to receive(:adapter_name).and_return('mysql2')
    end
  end
end
