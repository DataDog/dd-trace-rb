# frozen_string_literal: true

module Datadog
  module AppSec
    module ActionsHandler
      module StackTrace
        # Represent a stack trace with its id and message in message pack
        class Representor < Struct.new(:id, :message, :frames, keyword_init: true) # rubocop:disable Style/StructInheritance
          def to_msgpack(packer = nil)
            packer ||= MessagePack::Packer.new

            packer.write_map_header(4)
            packer.write('language')
            packer.write('ruby')
            packer.write('id')
            packer.write(id)
            packer.write('message')
            packer.write(message)
            packer.write('frames')
            packer.write(frames)
            packer
          end
        end
      end
    end
  end
end
