require 'rails/all'

require 'ddtrace' if ENV['TEST_AUTO_INSTRUMENT'] == true

if ENV['USE_SIDEKIQ']
  require 'sidekiq/testing'
  require 'datadog/tracing/contrib/sidekiq/server_tracer'
end

require 'datadog/tracing/contrib/rails/support/controllers'
require 'datadog/tracing/contrib/rails/support/middleware'
require 'datadog/tracing/contrib/rails/support/models'

# Patch Rails::Application so it doesn't raise an exception
# when we reinitialize applications.
Rails::Application.singleton_class.class_eval do
  def inherited(base)
    # raise "You cannot have more than one Rails::Application" if Rails.application
    super
    Rails.application = base.instance
    Rails.application.add_lib_to_load_path!
    ActiveSupport.run_load_hooks(:before_configuration, base.instance)
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

      instance_eval(&during_init)
    end

    klass.send(:define_method, :initialize) do |*args|
      super(*args)
      instance_eval(&during_init)
    end

    after_rails_application_creation
    before_test_init = before_test_initialize_block
    after_test_init = after_test_initialize_block

    klass.send(:define_method, :test_initialize!) do
      # we want to disable explicit instrumentation
      # when testing auto patching
      if ENV['TEST_AUTO_INSTRUMENT'] == 'true'
        require 'ddtrace/auto_instrument'
      else
        # Enables the auto-instrumentation for the testing application
        Datadog.configure do |c|
          c.tracing.instrument :rails
          c.tracing.instrument :redis if Gem.loaded_specs['redis'] && defined?(::Redis)
        end
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
    rails_test_application.instance.routes.append do
      delegate.call(self)
    end
  end

  def append_controllers!; end

  def draw_test_routes!(mapper)
    # Rails 3 accumulates these route drawing
    # blocks errantly, and this prevents them from
    # drawing more than once.
    return if @drawn

    test_routes = routes
    mapper.instance_exec do
      test_routes.each do |k, v|
        if k.is_a?(Array)
          send(k.first, k.last => v)
        else
          get k => v
        end
      end
    end
    @drawn = true
  end

  # Version of Ruby < 4 have initializers with persistent side effects:
  # actionpack-3.0.20/lib/action_view/railtie.rb:22
  def after_rails_application_creation
    Lograge.remove_existing_log_subscriptions if defined?(::Lograge)

    Rails.application.config.action_view = ActiveSupport::OrderedOptions.new

    # Prevent initializer from performing destructive operation on configuration.
    # This affects subsequent runs.
    allow(Rails.application.config.action_view).to receive(:delete).with(:stylesheet_expansions).and_return({})
    allow(Rails.application.config.action_view)
      .to receive(:delete).with(:javascript_expansions)
      .and_return(defaults: %w[prototype effects dragdrop controls rails])
    allow(Rails.application.config.action_view).to receive(:delete)
      .with(:embed_authenticity_token_in_remote_forms).and_return(true)
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

#
# ActiveSupport::OrderedOptions in Rails 3 doesn't respect the contract for `respond_to?`,
# which can include a second optional parameter:
# https://github.com/rails/rails/blob/v3.2.22.5/activesupport/lib/active_support/ordered_options.rb#L40-L42
# https://ruby-doc.org/core-2.0.0/Object.html#method-i-respond_to-3F
#
# This prevents us from using RSpec mocks on this this class.
#
# We fix that with this monkey-patching.
# Newer versions of Rails don't suffer from this issue.
#
require 'active_support/ordered_options'
module ActiveSupport
  class OrderedOptions
    def respond_to?(*_args)
      true
    end
  end
end
