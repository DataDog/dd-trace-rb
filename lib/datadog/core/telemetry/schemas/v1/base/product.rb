require 'datadog/core/telemetry/schemas/v1/base/appsec'
require 'datadog/core/telemetry/schemas/v1/base/profiler'
module Datadog
  module Core
    module Telemetry
      module Schemas
        module V1
          module Base
            # Describes attributes for products object
            class Product
              ERROR_NIL_ARGUMENTS = 'One of :appsec or :profiler must not be nil'.freeze
              ERROR_BAD_APPSEC_MESSAGE = ':appsec must be of type AppSec'.freeze
              ERROR_BAD_PROFILER_MESSAGE = ':profiler must be of type Profiler'.freeze

              attr_reader \
                :appsec,
                :profiler

              # @param appsec [Base::AppSec] Holds custom information about the appsec product
              # @param profiler [Base::Profiler] Holds custom information about the profiler product
              def initialize(appsec: nil, profiler: nil)
                validate(appsec: appsec, profiler: profiler)
                @appsec = appsec
                @profiler = profiler
              end

              private

              # Validates all arguments passed to the class on initialization
              #
              # @!visibility private
              def validate(appsec:, profiler:)
                raise ArgumentError, ERROR_NIL_ARGUMENTS if appsec.nil? && profiler.nil?
                raise ArgumentError, ERROR_BAD_APPSEC_MESSAGE if appsec && !appsec.is_a?(Base::AppSec)
                raise ArgumentError, ERROR_BAD_PROFILER_MESSAGE if profiler && !profiler.is_a?(Base::Profiler)
              end
            end
          end
        end
      end
    end
  end
end
