module Datadog
  module Transport
    # Data transfer object for generic data
    module Parcel
      include Kernel # Ensure that kernel methods are always available (https://sorbet.org/docs/error-reference#7003)

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
