# frozen_string_literal: true

require "json"

module Datadog
  module Profiling
    # Entity class used to represent metadata for a given profile
    class Flush
      attr_reader :start #: ::Time
      attr_reader :finish #: ::Time
      attr_reader :encoded_profile #: Datadog::Profiling::EncodedProfile
      attr_reader :code_provenance_file_name #: ::String
      attr_reader :code_provenance_data #: ::String?
      attr_reader :tags_as_array #: Array[[::String, ::String]]
      attr_reader :process_tags #: ::String
      attr_reader :internal_metadata_json #: ::String
      attr_reader :info_json #: ::String
      attr_reader :metrics_data #: ::String?

      # @rbs start: ::Time
      # @rbs finish: ::Time
      # @rbs encoded_profile: Datadog::Profiling::EncodedProfile
      # @rbs code_provenance_file_name: ::String
      # @rbs code_provenance_data: ::String?
      # @rbs tags_as_array: Array[[::String, ::String]]
      # @rbs process_tags: ::String
      # @rbs internal_metadata: ::Hash[::Symbol, ::String | bool | ::Numeric]
      # @rbs info_json: ::String
      # @rbs metrics_data: ::String?
      # @rbs return: void
      def initialize(
        start:,
        finish:,
        encoded_profile:,
        code_provenance_file_name:,
        code_provenance_data:,
        tags_as_array:,
        process_tags:,
        internal_metadata:,
        info_json:,
        metrics_data:
      )
        @start = start
        @finish = finish
        @encoded_profile = encoded_profile
        @code_provenance_file_name = code_provenance_file_name
        @code_provenance_data = code_provenance_data
        @tags_as_array = tags_as_array
        @process_tags = process_tags
        @internal_metadata_json = JSON.generate(internal_metadata)
        @info_json = info_json
        @metrics_data = metrics_data
      end
    end
  end
end
