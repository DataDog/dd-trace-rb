# frozen_string_literal: true

module Datadog
  module Core
    module Transport
      # Data transfer object.
      class Parcel
        def initialize(data, content_type: nil, content_encoding: nil)
          @data = data
          @content_type = content_type
          @content_encoding = content_encoding
        end

        attr_reader :data

        def length
          data.length
        end

        attr_reader :content_type

        attr_reader :content_encoding
      end
    end
  end
end
