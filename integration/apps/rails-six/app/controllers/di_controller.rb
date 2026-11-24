class DiController < ApplicationController
  def ar_serializer
    test = Test.create!
    serializer = Datadog::DI.component.serializer
    render json: serializer.serialize_value(test, deadline: serializer.serialization_deadline)
  end
end
