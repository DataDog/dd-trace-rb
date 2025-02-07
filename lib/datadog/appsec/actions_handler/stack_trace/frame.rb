# frozen_string_literal: true

module Datadog
  module AppSec
    module ActionsHandler
      module StackTrace
        # Formatted stack frame.
        # This class extends a Struct as it's required by Steep to be able to add a method to it.
        class Frame < Struct.new(:id, :text, :file, :line, :function, keyword_init: true) # rubocop:disable Style/StructInheritance
          def to_msgpack(packer = nil)
            packer ||= MessagePack::Packer.new

            packer.write_map_header(5)
            packer.write('id')
            packer.write(id)
            packer.write('text')
            packer.write(text)
            packer.write('file')
            packer.write(file)
            packer.write('line')
            packer.write(line)
            packer.write('function')
            packer.write(function)
            packer
          end
        end
      end
    end
  end
end
