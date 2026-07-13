# frozen_string_literal: true

require 'spec_helper'

require 'rubocop'
require 'rubocop/rspec/support'
require 'rubocop/custom_cops/open_feature_namespace_path_cop'

RSpec.describe CustomCops::OpenFeatureNamespacePathCop do
  subject(:cop) { described_class.new(config) }

  let(:config) { RuboCop::Config.new }

  it 'accepts an underscored namespace path' do
    expect_no_offenses(<<~RUBY, 'lib/datadog/open_feature/flag_evaluation/writer.rb')
      module Datadog
        module OpenFeature
          module FlagEvaluation
            class Writer
            end
          end
        end
      end
    RUBY
  end

  it 'rejects a namespace path without underscores' do
    expect_offense(<<~RUBY, 'lib/datadog/open_feature/flagevaluation/writer.rb')
      module Datadog
        module OpenFeature
          module FlagEvaluation
            class Writer
                  ^^^^^^ CustomCops/OpenFeatureNamespacePathCop: `Datadog::OpenFeature::FlagEvaluation::Writer` belongs in `lib/datadog/open_feature/flag_evaluation/writer.rb`, not `lib/datadog/open_feature/flagevaluation/writer.rb`.
            end
          end
        end
      end
    RUBY
  end

  it 'rejects a nested helper class kept in the parent file' do
    expect_offense(<<~RUBY, 'lib/datadog/open_feature/hooks/span_enrichment_hook.rb')
      module Datadog
        module OpenFeature
          module Hooks
            class SpanEnrichmentHook
              class Accumulator
                    ^^^^^^^^^^^ CustomCops/OpenFeatureNamespacePathCop: `Datadog::OpenFeature::Hooks::SpanEnrichmentHook::Accumulator` belongs in `lib/datadog/open_feature/hooks/span_enrichment_hook/accumulator.rb`, not `lib/datadog/open_feature/hooks/span_enrichment_hook.rb`.
              end
            end
          end
        end
      end
    RUBY
  end

  it 'accepts compact namespace declarations' do
    expect_no_offenses(<<~RUBY, 'lib/datadog/open_feature/hooks/flag_eval_hook.rb')
      class Datadog::OpenFeature::Hooks::FlagEvalHook
      end
    RUBY
  end

  context 'with an allowlisted legacy constant' do
    let(:config) do
      RuboCop::Config.new(
        'CustomCops/OpenFeatureNamespacePathCop' => {
          'AllowedConstants' => ['Datadog::OpenFeature::Transport::HTTP']
        }
      )
    end

    it 'accepts the existing path' do
      expect_no_offenses(<<~RUBY, 'lib/datadog/open_feature/transport.rb')
        module Datadog
          module OpenFeature
            module Transport
              class HTTP
              end
            end
          end
        end
      RUBY
    end
  end
end
