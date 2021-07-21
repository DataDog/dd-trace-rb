module Datadog
  module Security
    module Reactive
      class AddressHash < Hash
        def []=(key, value)
          super(key, value)
        end

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
