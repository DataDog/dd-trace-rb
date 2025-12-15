# frozen_string_literal: true

# steep thinks all of the arguments are nil here and does not know what ActiveRecord is.
# steep:ignore:start

Datadog::DI::Serializer.register(
  # This serializer uses a dynamic condition to determine its applicability
  # to a particular value. A simpler case could have been a serializer for
  # a particular class, but in this case any ActiveRecord model is covered
  # and they all have different classes.
  #
  # An alternative could have been to make DI specifically provide lookup
  # logic for "instances of classes derived from X", but a condition Proc
  # is more universal.
  condition: lambda { |value| ActiveRecord::Base === value }
) do |serializer, value, name:, depth:|
  # +serializer+ is an instance of DI::Serializer.
  # Use it to perform the serialization to primitive values.
  #
  # +value+ is the value to serialize. It should match the condition
  # provided above, meaning it would be an ActiveRecord::Base instance.
  #
  # +name+ is the name of the (local/instance) variable being serialized.
  # The name is used by DI for redaction (upstream of serialization logic),
  # and could potentially be used for redaction here also.
  #
  # +depth+ is the remaining depth for serializing collections and objects.
  # It should always be an integer.
  # Reduce it by 1 when invoking +serialize_value+ on the contents of +value+.
  # This serializer could also potentially do its own depth limiting.
  value_to_serialize = {
    attributes: value.attributes,
    new_record: value.new_record?,
  }
  serializer.serialize_value(value_to_serialize, depth: depth - 1, type: value.class)
end

# steep:ignore:end
