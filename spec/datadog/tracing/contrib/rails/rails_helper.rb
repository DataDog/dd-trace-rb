require 'datadog/tracing/contrib/support/spec_helper'

require 'logger'
require 'rails'

require 'spec/datadog/tracing/contrib/rails/support/configuration'
require 'spec/datadog/tracing/contrib/rails/support/database'
require 'spec/datadog/tracing/contrib/rails/support/application'

# logger
logger = Logger.new($stdout)
logger.level = Logger::INFO

# Rails settings
adapter = Datadog::Tracing::Contrib::Rails::Test::Database.load_adapter!
ENV['RAILS_ENV'] = 'test'
ENV['DATABASE_URL'] = adapter

# switch Rails import according to installed
# version; this is controlled with Appraisals
logger.info "Testing against Rails #{Rails.version} with adapter '#{adapter}'"

# ################################
# #### Testing Rails in RSpec ####
# ################################
#
# This Rails helper adds some shared contexts, which provide specs with a mock Rails application
# that can be fully configured with models, controllers, middleware and other settings, so you
# can test all kinds of Rails application setups.
#
# The quickest way to get started is by adding the shared context to your spec:
#
# ```
# describe 'My Rails test' do
#   include Rack::Test::Methods
#   include_context 'Rails test application'
# end
# ```
#
# Then you can add some of the following variables that will decorate your
# mock Rails application with features.
#
# ### Controllers ###
#
# Add controllers by setting the `routes` and `controllers` variables:
#
# ```
# describe 'My Rails test' do
#   include Rack::Test::Methods
#   include_context 'Rails test application'
#
#   let(:routes) { { '/' => 'test#index' } }
#   let(:controllers) { [controller] }
#
#   let(:controller) do
#     stub_const('TestController', Class.new(ActionController::Base) do
#       def index
#         head :ok
#       end
#     end)
#   end
#
#   it do
#     get '/'
#     expect(last_response).to be_ok
#   end
# end
# ```
#
# `routes` must be a Hash of paths to resource names, where the resource name must match the controller's name.
# `controllers` must be an Array of classes that implement `ActionController::Base`.
#
#
#
# ### Middleware ###
#
# Add middleware by setting the `rails_middleware` variable.
#
# ```
# describe 'My Rails test' do
#   include Rack::Test::Methods
#   include_context 'Rails test application'
#
#   let(:rails_middleware) { [middleware] }
#
#   let(:middleware) do
#     stub_const('TestMiddleware', Class.new do
#       def initialize(app)
#         @app = app
#       end
#
#       def call(env)
#         @app.call(env)
#       end
#     end)
#   end
# end
# ```
#
# `rails_middleware`:
#    Must be an Array of classes that implement the Rack middleware pattern.
#    It will apply the middleware with `use` in order of the Array.
#
#
#
# ### Rails configuration ###
#
# You can define custom Rails application settings by setting `initialize_block`:
#
# ```
# describe 'My Rails test' do
#   include Rack::Test::Methods
#   include_context 'Rails test application'
#
#   let(:initialize_block) do
#     super_block = super()
#     Proc.new do
#       self.instance_exec(&super_block)
#       config.action_dispatch.rescue_responses.merge!(
#         'CustomError' => :not_found
#       )
#     end
#   end
# end
# ```
#
# `initialize_block`:
#   Must be a Proc, which will be executed in the context of the Rails application.
#   NOTE: Right now you should call super() as shown above if you change this setting.
#
#
#
# ### Rails application lifecycle ###
#
# This implementation of Rails testing works differently than other testing suites.
# It does not create only one Rails application at load time.
# Instead it dynamically recreates Rails applications per example. This is how
# it is able to allow specs to define custom middleware and Rails configuration settings.
#
# To accomplish this, it uses RSpec's `let` blocks. `let` blocks are lazy variables that are
# only resolve their value once they are referenced for the first time. Every time thereafter,
# the return the same value they returned the first time they were referenced.
#
# The lifetime of these lazy variables is limited to the scope of an RSpec example, or an `it` block.
# Each time RSpec completes an `it`, it clears the old `let` variables. When it encounters the next
# `it` block, it will then re-run test setup again.
#
# This implementation of Rails testing takes advantage of this lifecycle. By defining the Rails application
# within a `let` block, it will recycle and recreate Rails applications for each `it` block, allowing specs
# to override `let` values, and thus customize application configuration per example.
#
# In a nutshell, the resulting sequence of events looks like:
#
# 1. RSpec loads "My Rails test" example group
# 2. "My Rails test" adds "Rails test application" context containing default `let` and `before`.
# 3. RSpec discovers `it` inside "My Rails test"
# 4. RSpec runs `before` inherited from "Rails test application", begins initializing the application.
# 5. RSpec uses the overridden `let` blocks from "My Rails test" to initialize the application.
# 6. `it` runs, calls `get '/'`, which references `let(:app)`, which references `let(:rails_test_application)`.
# 7. Request runs against `let(:rails_test_application)`.
# 8. `it` asserts and completes, RSpec discards all `let` values, including the Rails application.
# 9. RSpec looks for the next `it`. If it finds one, it loops back to #3. Otherwise it exits.
#
# Reinitializing Rails apps like this is somewhat complicated, and slow. However, it does allow the
# suite to test things that would otherwise not be possible. It is recommended for performance to keep
# assertions in as few `it` blocks as reasonably possible, so RSpec doesn't unnecessarily reload the
# Rails application.
#
# ### Some other important considerations ###
#
# - We would happily substitute this for a gem like `rspec-rails` if it were possible. However,
#   `rspec-rails` is for testing a Rails application. It doesn't create mock Rails apps for testing
#   against, like we need to in `ddtrace`.
# - The most challenging part of implementation is that Rails wasn't designed to be re-initialized
#   like this. There are a number of places, particularly with Rails::Configuration and Railties that
#   use global, constant-level variables to hold application configuration. This configuration can and
#   does often carry over between examples, sometimes breaking them. It's important to try to reset this
#   global configuration back to its original state between examples, whenever possible.
#
