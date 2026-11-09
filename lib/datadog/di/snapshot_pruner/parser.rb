# frozen_string_literal: true

require "strscan"
require_relative "node"

module Datadog
  module DI
    class SnapshotPruner
      # Builds the tree of JSON objects of an encoded snapshot in one scan,
      # recording each object's byte range and nesting level. Creates a
      # node for each JSON object.
      #
      # @api private
      class Parser
        # Bytes the scanner stops at outside strings.
        STRUCTURAL_BYTE = /[{}"]/

        # Remainder of a string after its opening quote, through the closing
        # quote, honoring backslash escapes.
        STRING_REMAINDER = /[^"\\]*+(?:\\.[^"\\]*+)*+"/m

        # Member name whose presence flags an object as not captured.
        NOT_CAPTURED_REASON = "notCapturedReason"

        # Encoded length of the +notCapturedReason+ name after its opening
        # quote, including the closing quote.
        NOT_CAPTURED_REASON_REMAINDER_SIZE = NOT_CAPTURED_REASON.bytesize + 1

        # Separator between a member name and its value.
        MEMBER_SEPARATOR = /\s*:\s*/

        # The +notCapturedReason+ value that flags an object as truncated
        # for depth.
        DEPTH_VALUE = /"depth"/

        # Byte value of the opening brace.
        OPEN_BRACE = "{".ord

        # Byte value of the closing brace.
        CLOSE_BRACE = "}".ord

        # Builds the object tree of an encoded snapshot.
        #
        # A +notCapturedReason+ member name flags its object: a string
        # value with the same text is skipped like any other value.
        #
        # @param json [String] the encoded snapshot, a JSON object
        # @return [Node] the root object
        # @raise [ArgumentError] when the document holds an unclosed string,
        #   a closing brace with no open object, or no closed root object
        def parse(json)
          scanner = StringScanner.new(json)
          open_nodes = []
          while scanner.skip_until(STRUCTURAL_BYTE)
            offset = scanner.pos - 1
            case json.getbyte(offset)
            when OPEN_BRACE
              node = Node.new(start_offset: offset, level: open_nodes.size, parent: open_nodes.last)
              open_nodes.last&.add_child(node)
              open_nodes.push(node)
            when CLOSE_BRACE
              node = open_nodes.pop
              raise ArgumentError, "closing brace at byte #{offset} without an open object" unless node

              node.close(scanner.pos)
              return node if open_nodes.empty?
            else
              unless skip_string(scanner, open_nodes.last)
                raise ArgumentError, "unclosed string starting at byte #{offset}"
              end
            end
          end
          raise ArgumentError, "no closed root object in the document"
        end

        private

        # Skips the string whose opening quote the scanner just passed, and
        # flags +enclosing_node+ when the string is a +notCapturedReason+
        # member name.
        #
        # @param scanner [StringScanner] scanner positioned after the opening quote
        # @param enclosing_node [Node, nil] the innermost open object
        # @return [Boolean] false when the string is not closed
        def skip_string(scanner, enclosing_node)
          string_start = scanner.pos
          remainder_size = scanner.skip(STRING_REMAINDER)
          return false unless remainder_size

          if enclosing_node &&
              remainder_size == NOT_CAPTURED_REASON_REMAINDER_SIZE &&
              scanner.string.byteslice(string_start, NOT_CAPTURED_REASON.bytesize) == NOT_CAPTURED_REASON &&
              scanner.skip(MEMBER_SEPARATOR)
            enclosing_node.mark_not_captured
            enclosing_node.mark_not_captured_depth if scanner.skip(DEPTH_VALUE)
          end
          true
        end
      end
    end
  end
end
