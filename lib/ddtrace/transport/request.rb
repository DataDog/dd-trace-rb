module Datadog
  module Transport
    # Defines request for transport operations
    class Request
      attr_reader \
        :parcel

      def initialize(parcel)
        @parcel = parcel
      end
    end
  end
end
