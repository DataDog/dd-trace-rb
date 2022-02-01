module Datadog
  module Security
    module Reactive
      # Address for Reactive Engine
      class AddressHash < Hash
        def addresses
          keys.flatten
        end

        def with(address)
          keys.select { |k| k.include?(address) }
        end
      end
    end
  end
end
