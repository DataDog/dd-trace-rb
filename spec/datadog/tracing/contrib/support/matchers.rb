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
