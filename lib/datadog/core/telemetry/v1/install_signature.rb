# frozen_string_literal: true

module Datadog
  module Core
    module Telemetry
      module V1
        # Describes attributes for install signature
        class InstallSignature
          using Core::Utils::Hash::Refinement

          attr_reader \
            :install_id,
            :install_type,
            :install_time

          # @param id [String,nil] Install ID
          # @param type [String,nil] Install type
          # @param type [String,nil] Install time
          def initialize(install_id:, install_type:, install_time:)
            @install_id = install_id
            @install_type = install_type
            @install_time = install_time
          end

          def to_h
            hash = {
              install_id: @install_id,
              install_type: @install_type,
              install_time: @install_time
            }
            hash.compact!
            hash
          end
        end
      end
    end
  end
end
