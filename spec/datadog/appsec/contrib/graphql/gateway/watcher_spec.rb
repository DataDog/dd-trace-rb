# frozen_string_literal: true

require "graphql"
require "datadog/appsec/native_output_helpers"
require "datadog/appsec/contrib/graphql/gateway/watcher"
require "datadog/appsec/contrib/graphql/gateway/multiplex"

RSpec.describe Datadog::AppSec::Contrib::GraphQL::Gateway::Watcher do
  let(:gateway) { Datadog::AppSec::Instrumentation::Gateway.new }
  let(:output_address) { "graphql.server.all_resolvers" }
  let(:schema) { Class.new(::GraphQL::Schema) }
  let(:query) { ::GraphQL::Query.new(schema, '{ post(slug: "example") { title } }') }
  let(:multiplex) do
    instance_double(::GraphQL::Execution::Multiplex, queries: [query])
  end

  before do
    described_class.watch_multiplex(gateway)
    allow(Datadog::AppSec::Context).to receive(:active).and_return(context)
  end

  subject(:consume) do
    payload = Datadog::AppSec::Contrib::GraphQL::Gateway::Multiplex.new(multiplex)
    gateway.push("graphql.multiplex", payload)
  end

  it_behaves_like "a native AppSec output consumer"
end
