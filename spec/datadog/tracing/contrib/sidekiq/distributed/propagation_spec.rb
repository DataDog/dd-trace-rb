# frozen_string_literal: true

require 'datadog/tracing/contrib/support/spec_helper'

require 'sidekiq'
require 'datadog'

RSpec.describe Datadog::Tracing::Contrib::Sidekiq::Distributed::Propagation do
  subject(:propagation) do
    described_class.new(
      propagation_style_inject: Datadog.configuration.tracing.propagation_style_inject,
      propagation_style_extract: Datadog.configuration.tracing.propagation_style_extract,
      propagation_extract_first: Datadog.configuration.tracing.propagation_extract_first
    )
  end

  it 'contains default inject propagation styles in its propagation styles list' do
    expect(propagation.instance_variable_get(:@propagation_styles).keys)
      .to include(*Datadog.configuration.tracing.propagation_style_inject)
    Datadog.configuration.tracing.propagation_style_inject.each do |style|
      expect(propagation.instance_variable_get(:@propagation_styles)[style]).to_not be_nil
    end
  end

  it 'contains default extract propagation styles in its propagation styles list' do
    expect(propagation.instance_variable_get(:@propagation_styles).keys)
      .to include(*Datadog.configuration.tracing.propagation_style_extract)
    Datadog.configuration.tracing.propagation_style_extract.each do |style|
      expect(propagation.instance_variable_get(:@propagation_styles)[style]).to_not be_nil
    end
  end
end
