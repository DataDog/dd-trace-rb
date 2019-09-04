require 'rails/all'
require 'ddtrace'

if ENV['USE_SIDEKIQ']
  require 'sidekiq/testing'
  require 'ddtrace/contrib/sidekiq/server_tracer'
end

require 'ddtrace/contrib/rails/support/controllers'
require 'ddtrace/contrib/rails/support/middleware'
require 'ddtrace/contrib/rails/support/models'

# Patch Rails::Application so it doesn't raise an exception
# when we reinitialize applications.
Rails::Application.class_eval do
  class << self
    def inherited(base)
      # raise "You cannot have more than one Rails::Application" if Rails.application
      super
      Rails.application = base.instance
      Rails.application.add_lib_to_load_path!
      ActiveSupport.run_load_hooks(:before_configuration, base.instance)
    end
  end
end

RSpec.shared_context 'Rails 3 base application' do
  include_context 'Rails controllers'
  include_context 'Rails middleware'
  include_context 'Rails models'

  let(:rails_base_application) do
    during_init = initialize_block
    klass = Class.new(Rails::Application) do
      redis_cache = [:redis_store, { url: ENV['REDIS_URL'] }]
      file_cache = [:file_store, '/tmp/ddtrace-rb/cache/']

      config.secret_token = 'f624861242e4ccf20eacb6bb48a886da'
      config.cache_store = ENV['REDIS_URL'] ? redis_cache : file_cache
      config.active_support.test_order = :random
      config.active_support.deprecation = :stderr
      config.consider_all_requests_local = true
      config.action_view.javascript_expansions = {}
      config.action_view.stylesheet_expansions = {}
      config.middleware.delete ActionDispatch::DebugExceptions if Rails.version >= '3.2.22.5'
      instance_eval(&during_init)
    end

    klass.send(:define_method, :initialize) do |*args|
      super(*args)
      instance_eval(&during_init)
    end

    before_test_init = before_test_initialize_block
    after_test_init = after_test_initialize_block

    klass.send(:define_method, :test_initialize!) do
      # Enables the auto-instrumentation for the testing application
      Datadog.configure do |c|
        c.use :rails
        c.use :redis if Gem.loaded_specs['redis'] && defined?(::Redis)
      end

      before_test_init.call
      initialize!
      after_test_init.call
    end
    klass
  end

  def append_routes!
    # Make sure to load controllers first
    # otherwise routes won't draw properly.
    controllers
    delegate = method(:draw_test_routes!)

    # Then set the routes
    if Rails.version >= '3.2.22.5'
      rails_test_application.instance.routes.append do
        delegate.call(self)
      end
    else
      rails_test_application.instance.routes.draw do
        delegate.call(self)
      end
    end
  end

  def draw_test_routes!(mapper)
    # Rails 3 accumulates these route drawing
    # blocks errantly, and this prevents them from
    # drawing more than once.
    return if @drawn

    test_routes = routes
    mapper.instance_exec do
      if Rails.version >= '3.2.22.5'
        test_routes.each do |k, v|
          get k => v
        end
      else
        test_routes.each do |k, v|
          get k, to: v
        end
      end
    end
    @drawn = true
  end

  # Rails 3 leaves a bunch of global class configuration on Rails::Railtie::Configuration in class variables
  # We need to reset these so they don't carry over between example runs
  def reset_rails_configuration!
    Rails.class_variable_set(:@@application, nil)
    Rails::Application.class_variable_set(:@@instance, nil)
    if Rails::Railtie::Configuration.class_variable_defined?(:@@app_middleware)
      Rails::Railtie::Configuration.class_variable_set(:@@app_middleware, Rails::Configuration::MiddlewareStackProxy.new)
    end
    Rails::Railtie::Configuration.class_variable_set(:@@app_generators, nil)
    Rails::Railtie::Configuration.class_variable_set(:@@to_prepare_blocks, nil)
  end
end
