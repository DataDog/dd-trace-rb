# Remove vendor-specific syntax (e.g quoting)
# to allow for unified query matching.
#
# @example Exact match
#   expect('SELECT * FROM `tbl`').to match_normalized_sql('SELECT * FROM tbl')
#
# @example Custom matching
#   expect('SELECT * FROM `tbl` LIMIT 1').to match_normalized_sql(include 'LIMIT')
RSpec::Matchers.define :match_normalized_sql do |expected|
  match do |actual|
    @actual = actual
      .gsub(/[`"]/, '') # Remove all query token quotations. String quotations are left untouched.
      .gsub(/\$\d+/, '?') # Convert Postgres placeholder '$1' to '?'
      .gsub(/:\w+/, '?') # Convert Sqlite placeholder ':value' to '?'

    values_match?(expected, @actual)
  end

  diffable
end

# Check if the provided string is a valid IPv4 or IPv6 address.
RSpec::Matchers.define :be_an_ip_address do
  match do |actual|
    !!IPAddr.new(actual)
  rescue IPAddr::InvalidAddressError
    false
  end

  description do
    "be an IPv4 or IPv6 address"
  end
end
