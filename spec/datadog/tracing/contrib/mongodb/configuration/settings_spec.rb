require 'datadog/tracing/contrib/mongodb/configuration/settings'
require 'datadog/tracing/contrib/service_name_settings_examples'

# TODO: JRuby 10.0 - Remove this skip after MongoDB adds support for JRuby 10.0: https://github.com/mongodb/mongo-ruby-driver#mongodb-ruby-driver
# The tests fail on an error related to the bson_ruby gem's NativeService.
RSpec.describe Datadog::Tracing::Contrib::MongoDB::Configuration::Settings, skip: PlatformHelpers.jruby_100? do
  it_behaves_like 'service name setting', 'mongodb'
end
