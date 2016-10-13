require 'logger'
require 'bundler/setup'
require 'minitest/autorun'

require 'rails'

# logger
logger = Logger.new(STDOUT)
logger.level = Logger::INFO

# Rails settings
ENV['RAILS_ENV'] = 'test'
ENV['DATABASE_URL'] = 'sqlite3::memory:'

# switch Rails import according to installed
# version; this is controlled with Appraisals
logger.info "Testing against Rails #{Rails.version}"

case Rails.version
when '5.0.0.1'
  require 'contrib/rails/apps/rails5'
when '4.2.7.1'
  require 'contrib/rails/apps/rails4'
when '3.2.22.5'
  ENV['DATABASE_URL'] = 'sqlite3://localhost/:memory:'
  require 'test/unit'
  require 'contrib/rails/apps/rails3'
else
  logger.error 'A Rails app for this version is not found!'
end

# overriding Rails components for testing purposes
require 'contrib/rails/core_extensions'
