module Datadog
  module Transport
    # Data transfer object for generic data
    module Parcel
      include Kernel

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
