require 'datadog/tracing/contrib/support/spec_helper'
require 'rails'
require 'datadog/tracing/contrib/rails/integration'

RSpec.describe Datadog::Core::Configuration::Option do
  around do |example|
    Datadog.registry[:rails].reset_configuration!
    Datadog.shutdown!
    Datadog.configuration.reset!
    example.run
    Datadog.registry[:rails].reset_configuration!
    Datadog.shutdown!
    Datadog.configuration.reset!
  end

  it 'computes names for instrumented Rails options from the settings path' do
    Datadog.configure do |c|
      c.tracing.instrument :rails, middleware_names: true
    end

    expect(Datadog.configuration.tracing[:rails].send(:resolve_option, :middleware_names).name)
      .to eq('tracing.rails.middleware_names')
    expect(Datadog.configuration.tracing[:rails].send(:resolve_option, :enabled).name)
      .to eq('tracing.rails.enabled')
  end
end
