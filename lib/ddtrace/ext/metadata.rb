# typed: true
module Datadog
  module Ext
    # Trace and span tags that represent meta information
    # regarding the trace. These fields are normally only used
    # internally, and can have special meaning to downstream
    # trace processing.
    # @public_api
    module Metadata
      # Name of package that was instrumented
      TAG_COMPONENT = 'component'.freeze
      # Type of operation being performed (e.g. )
      TAG_OPERATION = 'operation'.freeze
      # Hostname of external service interacted with
      TAG_PEER_HOSTNAME = 'peer.hostname'.freeze
      # Name of external service that performed the work
      TAG_PEER_SERVICE = 'peer.service'.freeze
    end
  end
end
