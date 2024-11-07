# frozen_string_literal: true

Datadog::DI::Serializer.register(condition: lambda { |value| ActiveRecord::Base === value } # steep:ignore
) do |serializer, value, name:, depth:|
  value_to_serialize = {
    attributes: value.attributes,
  }
  serializer.serialize_value(value_to_serialize, depth: depth ? depth - 1 : nil, type: value.class)
end
