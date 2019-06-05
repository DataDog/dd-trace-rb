module Datadog
  module Transport
    # Defines request for transport operations
    class Request
      attr_reader \
        :parcel,
        :route

      def initialize(route, parcel)
        @route = route
        @parcel = parcel
      end
    end
  end
end
