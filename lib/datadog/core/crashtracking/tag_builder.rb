# frozen_string_literal: true

require_relative '../tag_builder'
require_relative '../utils'
require_relative '../environment/process'

module Datadog
  module Core
    module Crashtracking
      # This module builds a hash of tags
      module TagBuilder
        def self.call(settings)
          hash = Core::TagBuilder.tags(settings).merge(
            'is_crash' => 'true',
          )

          if settings.experimental_propagate_process_tags_enabled
            process_tags = Environment::Process.serialized
            hash['process_tags'] = process_tags unless process_tags.empty?
          end

          Utils.encode_tags(hash)
        end
      end
    end
  end
end
