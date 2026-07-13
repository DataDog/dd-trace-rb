# frozen_string_literal: true

require 'spec_helper'

require 'rubocop'
require 'rubocop/rspec/support'
require 'rubocop/custom_cops/open_feature_steep_ignore_cop'

RSpec.describe CustomCops::OpenFeatureSteepIgnoreCop do
  subject(:cop) { described_class.new(config) }

  let(:config) { RuboCop::Config.new }

  it 'rejects a Steep suppression' do
    expect_offense(<<~RUBY, 'lib/datadog/open_feature/hooks/span_enrichment_hook.rb')
      value = compute_value # steep:ignore IncompatibleAssignment
                              ^^^^^^^^^^^^ CustomCops/OpenFeatureSteepIgnoreCop: Do not suppress OpenFeature type errors with `steep:ignore`; model the type in RBS instead.
    RUBY
  end

  it 'accepts ordinary Steep annotations' do
    expect_no_offenses(<<~RUBY, 'lib/datadog/open_feature/provider.rb')
      value = compute_value #: String
    RUBY
  end

  context 'with an allowlisted compatibility suppression' do
    let(:config) do
      RuboCop::Config.new(
        'CustomCops/OpenFeatureSteepIgnoreCop' => {
          'AllowedComments' => [
            'lib/datadog/open_feature/evaluation_engine.rb:# steep:ignore IncompatibleAssignment'
          ]
        }
      )
    end

    it 'accepts the existing comment' do
      expect_no_offenses(<<~RUBY, 'lib/datadog/open_feature/evaluation_engine.rb')
        ErrorClass = Class.new(StandardError) # steep:ignore IncompatibleAssignment
      RUBY
    end
  end
end
