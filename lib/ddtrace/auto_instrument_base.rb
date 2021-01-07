module Datadog
  # base methods stubbed for adding auto instrument extensions
  module AutoInstrumentBase
    def self.included(base)
      base.send(:extend, InstanceMethods)
      base.send(:include, InstanceMethods)
    end
    # stubbed methods for adding auto instrument
    module InstanceMethods
      def add_auto_instrument; end
    end
  end
end
