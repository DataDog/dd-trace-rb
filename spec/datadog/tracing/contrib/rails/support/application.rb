require 'rails/all'

RSpec.shared_context 'Rails test application' do
  version = Gem::Version.new(Rails.version)
  major_version, = version.segments

  require "datadog/tracing/contrib/rails/support/rails#{major_version}"
  include_context "Rails #{major_version} base application"
end
