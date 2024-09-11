# frozen_string_literal: true

require 'datadog/appsec/spec_helper'
require 'datadog/appsec/contrib/graphql/integration'

RSpec.describe Datadog::AppSec::Contrib::GraphQL::Integration do
  describe '.ast_node_classes_defined?' do
    it 'returns true when all AST node classes are defined' do
      expect(described_class.ast_node_classes_defined?).to be(true)
    end

    it 'returns false when at least one of AST node classes is not defined' do
      hide_const('GraphQL::Language::Nodes::Field')
      expect(described_class.ast_node_classes_defined?).to be(false)
    end
  end
end
