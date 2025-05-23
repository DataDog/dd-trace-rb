class DiController < ApplicationController
  def ar_serializer
    test = Test.create!
    render json: Datadog::DI.component.serializer.serialize_value(test)
  end
end
