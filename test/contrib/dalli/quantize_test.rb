require 'helper'
require 'dalli'
require 'ddtrace'
require 'ddtrace/contrib/dalli/quantize'

module Datadog
  module Contrib
    module Dalli
      class QuantizeTest < Minitest::Test
        def test_command_format
          op = :set
          args = [123, 'foo', nil]

          assert_equal('set 123 foo', Quantize.format_command(op, args))
        end

        def test_command_truncation
          op = :set
          args = ['foo', 'A' * 100]
          command = Quantize.format_command(op, args)

          assert_equal(Quantize::MAX_CMD_LENGTH, command.size)
          assert(command.end_with?('...'))
          assert_equal('set foo ' + 'A' * 89 + '...', command)
        end

        def test_regression_different_encodings
          op = :set
          args = ["\xa1".force_encoding('iso-8859-1'), "\xa1\xa1".force_encoding('euc-jp')]

          assert_match(/BLOB \(OMITTED\)/, Quantize.format_command(op, args))
        end
      end
    end
  end
end
