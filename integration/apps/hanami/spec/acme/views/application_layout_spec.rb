require "spec_helper"

RSpec.describe Acme::Views::ApplicationLayout, type: :view do
  let(:layout)   { Acme::Views::ApplicationLayout.new({ format: :html }, "contents") }
  let(:rendered) { layout.render }

  it 'contains application name' do
    expect(rendered).to include('Acme')
  end
end
