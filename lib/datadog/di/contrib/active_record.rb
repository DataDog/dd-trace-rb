# frozen_string_literal: true

Datadog::DI::Serializer.register(condition: lambda { |value| ActiveRecord::Base === value } # steep:ignore
) do |serializer, value, name:, depth:|
  # steep thinks all of the arguments are nil here
  # steep:ignore:start
  value_to_serialize = {
    attributes: value.attributes,
  }
  serializer.serialize_value(value_to_serialize, depth: depth ? depth - 1 : nil, type: value.class)
  # steep:ignore:end
end
