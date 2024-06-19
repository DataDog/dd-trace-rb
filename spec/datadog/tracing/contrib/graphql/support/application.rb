require 'datadog/tracing/contrib/support/spec_helper'

require 'active_model/railtie'
require 'action_controller/railtie'
require 'action_mailer/railtie'
require 'action_view/railtie'
require 'active_job/railtie'
require 'action_cable/engine'
require 'sprockets/railtie'
require 'rails/test_unit/railtie'

require 'logger'
require 'graphql'
require 'rack/test'

require 'spec/datadog/tracing/contrib/rails/support/configuration'
require 'spec/datadog/tracing/contrib/rails/support/application'

# logger
logger = Logger.new($stdout)
logger.level = Logger::INFO

# Rails settings
ENV['RAILS_ENV'] = 'test'

# switch Rails import according to installed
# version; this is controlled with Appraisals
logger.info "Testing against Rails #{Rails.version} with GraphQL #{::GraphQL::VERSION}"

class TestUserType < ::GraphQL::Schema::Object
  field :id, ::GraphQL::Types::ID, null: false
  field :name, ::GraphQL::Types::String, null: true
  field :created_at, ::GraphQL::Types::String, null: false
  field :updated_at, ::GraphQL::Types::String, null: false
end

class TestGraphQLQuery < ::GraphQL::Schema::Object
  field :user, TestUserType, null: false, description: 'Find an user by ID' do
    argument :id, ::GraphQL::Types::ID, required: true
  end

  def user(id:)
    return OpenStruct.new(id: id, name: 'Caniche') if Integer(id) == 10

    OpenStruct.new(id: id, name: 'Bits')
  end

  field :userByName, TestUserType, null: false, description: 'Find an user by name' do
    argument :name, ::GraphQL::Types::String, required: true
  end

  # rubocop:disable Naming/MethodName
  def userByName(name:)
    return OpenStruct.new(id: 10, name: name) if name == 'Caniche'

    OpenStruct.new(id: 1, name: name)
  end
  # rubocop:enable Naming/MethodName
end

class TestGraphQLSchema < ::GraphQL::Schema
  query(TestGraphQLQuery)
end

def prepare_variables(variables_param)
  case variables_param
  when String
    if variables_param.present?
      JSON.parse(variables_param) || {}
    else
      {}
    end
  when Hash
    variables_param
  when ActionController::Parameters
    variables_param.to_unsafe_hash # GraphQL-Ruby will validate name and type of incoming variables.
  when nil
    {}
  else
    raise ArgumentError, "Unexpected parameter: #{variables_param}"
  end
end

RSpec.shared_context 'with GraphQL schema' do
  let(:operation) { Datadog::AppSec::Reactive::Operation.new('test') }
  let(:schema) { TestGraphQLSchema }
end

RSpec.shared_context 'with GraphQL multiplex' do
  include_context 'with GraphQL schema'

  let(:first_query) { ::GraphQL::Query.new(schema, 'query test{ user(id: 1) { name } }') }
  let(:second_query) { ::GraphQL::Query.new(schema, 'query test{ user(id: 10) { name } }') }
  let(:third_query) { ::GraphQL::Query.new(schema, 'query { userByName(name: "Caniche") { id } }') }
  let(:queries) { [first_query, second_query, third_query] }
  let(:context) { { :dataloader => GraphQL::Dataloader.new(nonblocking: nil) } }
  let(:multiplex) do
    ::GraphQL::Execution::Multiplex.new(schema: schema, queries: queries, context: context, max_complexity: nil)
  end
end

RSpec.shared_context 'GraphQL test application' do
  let(:no_db) { true }

  include_context 'Rails test application'
  include_context 'with GraphQL schema'
  include Rack::Test::Methods

  let(:routes) do
    {
      [:post, '/graphql'] => 'graphql#execute'
    }
  end
  let(:controllers) { [controller] }

  let(:controller) do
    stub_const(
      'GraphqlController',
      Class.new(ActionController::Base) do
        # skip CSRF token check for non-GET requests
        begin
          if respond_to?(:skip_before_action)
            skip_before_action :verify_authenticity_token
          else
            skip_before_filter :verify_authenticity_token
          end
        rescue ArgumentError # :verify_authenticity_token might not be defined
          nil
        end

        def execute
          result = if params[:_json]
                     queries = params[:_json].map do |param|
                       {
                         query: param[:query],
                         operation_name: param[:operationName],
                         variables: prepare_variables(param[:variables]),
                         context: {}
                       }
                     end
                     TestGraphQLSchema.multiplex(queries)
                   else
                     TestGraphQLSchema.execute(
                       query: params[:query],
                       operation_name: params[:operationName],
                       variables: prepare_variables(params[:variables]),
                       context: {}
                     )
                   end
          render json: result
        end
      end
    )
  end
end
