require 'spec_helper'

require 'logger'
require 'rails'

require 'ddtrace/contrib/rails/support/configuration'
require 'ddtrace/contrib/rails/support/database'
require 'ddtrace/contrib/rails/support/application'

# logger
logger = Logger.new(STDOUT)
logger.level = Logger::INFO

# Rails settings
connector = Datadog::Contrib::Rails::Test::Database.configure!
ENV['RAILS_ENV'] = 'test'
ENV['DATABASE_URL'] = connector

# switch Rails import according to installed
# version; this is controlled with Appraisals
logger.info "Testing against Rails #{Rails.version} with connector '#{connector}'"
