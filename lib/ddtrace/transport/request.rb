module Datadog
  module Transport
    # Defines request for transport operations
    class Request
      attr_reader \
        :parcel, :trace_count, :content_type

      def initialize(parcel, trace_count, content_type)
        @parcel = parcel
        @trace_count = trace_count
        @content_type = content_type
      end
    end
  end
end
