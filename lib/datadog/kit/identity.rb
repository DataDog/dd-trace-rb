# typed: false

module Datadog
  module Kit
    # Tracking identity via traces
    module Identity
      # Attach user information to the trace
      #
      # Values must be strings. Keys are free form, although the following keys have specific meanings:
      # - id: Mandatory. Username or client id extracted from the access token or
      #   Authorization header in the inbound request from outside the system.
      # - email: Email of the authenticated user associated to the trace.
      # - name: User-friendly name. To be displayed in the UI if set.
      # - session_id: Session ID of the authenticated user.
      # - role: Actual/assumed role the client is making the request under
      #   extracted from token or application security context.
      # - scope: Scopes or granted authorities the client currently possesses
      #   extracted from token or application security context. The value would
      #   come from the scope associated with an OAuth 2.0 Access Token or an
      #   attribute value in a SAML 2.0 Assertion.
      def self.set_user(trace, data = {})
        raise ArgumentError, 'missing required key: :id' unless data[:id]

        # enforce types
        data.each do |k, v|
          raise TypeError, "#{k.inspect} must be a String" unless v.is_a?(String)
        end

        # set tags once data is made consistent
        data.each do |k, v| # rubocop:disable Style/CombinableLoops
          trace.set_tag("usr.#{k}", v)
        end
      end
    end
  end
end
