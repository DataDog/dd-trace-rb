module Datadog
  module Transport
    # Data transfer object for generic data
    # @abstract
    module Parcel
      attr_reader \
        :data

      def initialize(data)
        @data = data
      end

      def encode_with(encoder)
        raise NotImplementedError
      end
    end
  end
end
