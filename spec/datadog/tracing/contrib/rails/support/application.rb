require 'spec/datadog/tracing/contrib/rails/support/deprecation'

require 'rails/all'
require 'ddtrace'

RSpec.shared_context 'Rails test application' do
  if Rails.version >= '6.0'
    require 'datadog/tracing/contrib/rails/support/rails6'
    include_context 'Rails 6 base application'
  elsif Rails.version >= '5.0'
    require 'datadog/tracing/contrib/rails/support/rails5'
    include_context 'Rails 5 base application'
  elsif Rails.version >= '4.0'
    require 'datadog/tracing/contrib/rails/support/rails4'
    include_context 'Rails 4 base application'
  elsif Rails.version >= '3.2'
    require 'datadog/tracing/contrib/rails/support/rails3'
    include_context 'Rails 3 base application'
  else
    logger.error 'A Rails app for this version is not found!'
  end
end
