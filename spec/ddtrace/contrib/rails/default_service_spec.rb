require 'ddtrace/contrib/rails/rails_helper'

RSpec.describe 'Rails default service' do
  include_context 'Rails test application'

  before { app }

  context 'span without explicit service' do
    subject! { tracer.trace('name') {} }

    it 'has default service' do
      expect(span.service).to eq(app_name)
    end
  end
end
