require 'rails/all'
require 'ddtrace'

if ENV['USE_SIDEKIQ']
  require 'sidekiq/testing'
  require 'ddtrace/contrib/sidekiq/server_tracer'
end

require 'lograge' if ENV['USE_LOGRAGE'] == true

RSpec.shared_context 'Rails base application' do
  if Rails.version >= '6.0'
    require 'ddtrace/contrib/rails/support/rails6'
    include_context 'Rails 6 base application'
  elsif Rails.version >= '5.0'
    require 'ddtrace/contrib/rails/support/rails5'
    include_context 'Rails 5 base application'
  elsif Rails.version >= '4.0'
    require 'ddtrace/contrib/rails/support/rails4'
    include_context 'Rails 4 base application'
  elsif Rails.version >= '3.0'
    require 'ddtrace/contrib/rails/support/rails3'
    include_context 'Rails 3 base application'
  else
    logger.error 'A Rails app for this version is not found!'
  end

  # for log_injection testing
  let(:log_output) { StringIO.new }
  let(:logger) do
    Logger.new(log_output)
  end

  let(:initialize_block) do
    middleware = rails_middleware
    debug_mw = debug_middleware
    logger = self.logger

    proc do
      # ActiveSupport::TaggedLogging was introduced in 3.2
      # https://github.com/rails/rails/blob/3-2-stable/activesupport/CHANGELOG.md#rails-320-january-20-2012
      if Rails.version >= '3.2'
        if ENV['USE_TAGGED_LOGGING'] == true
          config.log_tags = ENV['LOG_TAGS'] || []
          config.logger = ActiveSupport::TaggedLogging.new(logger)
        end
      end

      if ENV['USE_LOGRAGE'] == true
        config.logger = logger

        unless ENV['LOGRAGE_CUSTOM_OPTIONS'].nil?
          config.lograge.custom_options = ENV['LOGRAGE_CUSTOM_OPTIONS']
        end

        if ENV['LOGRAGE_DISABLED'].nil?
          config.lograge.enabled = true
          config.lograge.base_controller_class = 'LogrageTestController'
          config.lograge.logger = logger
        else
          config.lograge.enabled = false
        end
      # ensure no test leakage from other tests
      elsif config.respond_to?(:lograge)
        config.lograge.enabled = false
        config.lograge.keep_original_rails_log = true
      end

      config.middleware.insert_after ActionDispatch::ShowExceptions, debug_mw
      middleware.each { |m| config.middleware.use m }
    end
  end

  let(:before_test_initialize_block) do
    proc do
      append_routes!
    end
  end

  let(:after_test_initialize_block) do
    proc do
      # Rails autoloader recommends controllers to be loaded
      # after initialization. This will be enforced when `zeitwerk`
      # becomes the only supported autoloader.
      append_controllers!

      # Force connection to initialize, and dump some spans
      application_record.connection
    end
  end
end
