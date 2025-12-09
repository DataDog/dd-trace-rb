require 'datadog/tracing/contrib/rails/ext'
require 'datadog/tracing/contrib/rails/rails_helper'
require 'datadog/tracing/contrib/view_component/utils'
require 'datadog/tracing/contrib/view_component/integration'

require 'view_component'

RSpec.describe 'ViewComponent integration tests', execute_in_fork: Rails.version.to_i >= 8 do
  include_context 'Rails test application'
  include ViewComponent::TestHelpers

  let(:initialize_block) do
    if Gem.loaded_specs["view_component"].version <= Gem::Version.new("3")
      require "view_component/engine"
    end

    proc do
      config.view_component.instrumentation_enabled = true
      if Gem.loaded_specs["view_component"].version >= Gem::Version.new("4")
        config.view_component.previews.controller = "TestController"
      else
        config.view_component.use_deprecated_instrumentation_name = false
        config.view_component.test_controller = "TestController"
      end
    end
  end

  let(:component) do
    stub_const("TestComponent", Class.new(ViewComponent::Base) do
      def call
        content_tag(:h1, "Hello")
      end
    end)
  end

  let(:controllers) { [controller] }

  let(:controller) do
    stub_const('TestController', Class.new(ActionController::Base))
  end

  before do
    Datadog.configure do |c|
      if Gem.loaded_specs["view_component"].version >= Gem::Version.new("3")
        c.tracing.instrument :view_component
      else
        c.tracing.instrument :view_component, use_deprecated_instrumentation_name: true
      end
    end

    allow(ENV).to receive(:[]).and_call_original

    app
  end

  it "stores instrumentation data when rendering" do
    controller.render(component.new)
    span = spans.find { |s| s.name == "view_component.render" }

    expect(span.name).to eq("view_component.render")
    expect(span.resource).to eq("TestComponent")
    expect(span.type).to eq(Datadog::Tracing::Metadata::Ext::HTTP::TYPE_TEMPLATE)

    expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq("view_component")
    expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION)).to eq("render")

    expect(span.get_tag("view_component.component_name")).to eq("TestComponent")
    expect(span.get_tag("view_component.component_identifier")).to eq("integration_test_spec.rb")
  end
end
