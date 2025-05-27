# frozen_string_literal: true

require 'action_view/testing/resolvers'

RSpec.shared_context 'Rails controllers' do
  let(:controllers) { [] }
  let(:routes) { {} }
end
