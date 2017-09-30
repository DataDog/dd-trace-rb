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
      end
    end
  end
end
