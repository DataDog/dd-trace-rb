module Datadog
  module Utils
    # Base class for converting data source to tags
    class BaseTagConverter
      def name(_name)
        raise NotImplementedError
      end

      def value(_name, _source)
        raise NotImplementedError
      end
    end
  end
end
