# frozen_string_literal: true

require_relative '../core/tag_builder'
require_relative '../core/utils'

require 'set'

module Datadog
  module Profiling
    # Builds a hash of default plus user tags to be included in a profile
    #
    # @api private
    module TagBuilder
      include Datadog::Profiling::Ext::Transport::HTTP # Tag name constants

      # When changing or adding profiling-related tags, make sure they are
      # kept in sync with
      # https://docs.google.com/spreadsheets/d/1LOGMf4c4Avbtn36uZ2SWvhIGKRPLM1BoWkUP4JYj7hA/
      # (Datadog internal link).
      #
      # For consistency between the different profilers, every tag should be
      # vetted before it gets reported with a profile, as otherwise it's too
      # easy to end up with different tags in different languages.
      ALLOWED_TAGS = Set.new(
        [
          'env',
          'service',
          'version',
          'git.commit.sha',
          'git.repository_url',
          'host',
          'language',
          'runtime',
          'runtime_engine',
          'runtime_platform',
          'runtime_version',
          'runtime-id',
          'process_id',
          'profiler_version',
          'profile_seq',
        ]
      ).freeze

      def self.call(
        settings:,
        profile_seq:,
        profiler_version: Core::Environment::Identity.gem_datadog_version
      )
        hash = Core::TagBuilder.tags(settings).merge(
          FORM_FIELD_TAG_PROFILER_VERSION => profiler_version,
          'profile_seq' => profile_seq.to_s,
        )
        user_tag_keys = settings.tags.keys
        hash.keep_if { |tag| user_tag_keys.include?(tag) || ALLOWED_TAGS.include?(tag) }
        Core::Utils.encode_tags(hash)
      end
    end
  end
end
