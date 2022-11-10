# frozen_string_literal: true

require_relative '../../../distributed/propagation'
require_relative 'b3'
require_relative 'b3_single'
require_relative 'datadog'

module Datadog
  module Tracing
    module Contrib
      module GRPC
        module Distributed
          # Extracts and injects propagation through gRPC metadata.
          class Propagation < Tracing::Distributed::Propagation
            def initialize
              super(
                propagation_styles: {
                  Tracing::Configuration::Ext::Distributed::PROPAGATION_STYLE_B3 => B3.new,
                  Tracing::Configuration::Ext::Distributed::PROPAGATION_STYLE_B3_SINGLE_HEADER => B3Single.new,
                  Tracing::Configuration::Ext::Distributed::PROPAGATION_STYLE_DATADOG => Datadog.new,
                })
            end

            # DEV: Singleton kept until a larger refactor is performed.
            # DEV: See {Datadog::Tracing::Distributed::Propagation#initialize} for more information.
            INSTANCE = Propagation.new
          end
        end
      end
    end
  end
end
