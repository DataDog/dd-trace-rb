version = Gem::Version.new(Rails.version)
major_version, = version.segments

require_relative 'base'
require_relative "rails#{major_version}"

RSpec.shared_context 'Rails test application' do
  include_context 'Rails base application' do
    include_context "Rails #{major_version} test application"
  end

  after do
    without_warnings { Datadog.configuration.reset! }

    Datadog.configuration.tracing[:rails].reset_options!
    Datadog.configuration.tracing[:rack].reset_options!
    Datadog.configuration.tracing[:redis].reset_options!
  end
end
