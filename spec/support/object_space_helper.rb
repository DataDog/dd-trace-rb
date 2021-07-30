require 'objspace'

module ObjectSpaceHelper
  class << self
    def estimate_bytesize_supported?
      ::ObjectSpace.respond_to?(:memsize_of) &&
        ::ObjectSpace.memsize_of(Object.new) > 0 # Sanity check for non-CRuby
    end

    def estimate_bytesize(object)
      return nil unless estimate_bytesize_supported?

      # Rough calculation of bytesize; not very accurate.
      object.instance_variables.inject(::ObjectSpace.memsize_of(object)) do |sum, var|
        sum + ::ObjectSpace.memsize_of(object.instance_variable_get(var))
      end
    end
  end
end
