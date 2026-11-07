# frozen_string_literal: true

require "json"

require_relative "array_node"
require_relative "fragment_node"
require_relative "object_node"
require_relative "prunable"

module Datadog
  module DI
    module SnapshotEncoder
      # Builds the encoded tree of one snapshot payload: encodes every
      # primitive and envelope scalar once, records the exact size of
      # every node, and registers the primitives and collections of the
      # captured data that the pruner can replace or cut.
      #
      # The walk keeps its pending Hashes and Arrays on an explicit stack,
      # so payload nesting is limited by memory and raises no
      # SystemStackError. Every Hash and Array is recognized with
      # +Hash ===+ and +Array ===+ and iterated through the Hash and Array
      # base class methods, so a subclass is encoded as its base class.
      #
      # @api private
      class TreeBuilder
        # Iterates a Hash, or a Hash subclass instance, as a Hash.
        HASH_EACH_PAIR = ::Hash.instance_method(:each_pair)

        # Iterates an Array, or an Array subclass instance, as an Array.
        ARRAY_EACH = ::Array.instance_method(:each)

        # JSON text of +true+.
        TRUE_JSON = "true"
        # JSON text of +false+.
        FALSE_JSON = "false"
        # JSON text of +nil+.
        NULL_JSON = "null"

        # Name of the member whose String and Symbol values share one
        # encoding per payload.
        TYPE_MEMBER = "type"

        # Length of an +entries+ member that is a key-value pair.
        PAIR_LENGTH = 2

        # Role of a value outside the captured data.
        ROLE_ENVELOPE = :envelope
        # Role of the payload Hash.
        ROLE_ROOT = :root
        # Role of the payload's +debugger+ Hash.
        ROLE_DEBUGGER = :debugger
        # Role of the +debugger.snapshot+ Hash.
        ROLE_SNAPSHOT = :snapshot
        # Role of the +debugger.snapshot.captures+ Hash.
        ROLE_CAPTURES = :captures
        # Role of the +lines+ Hash of +captures+.
        ROLE_LINES = :lines
        # Role of a capture set.
        ROLE_CAPTURE_SET = :capture_set
        # Role of a variable map.
        ROLE_VARIABLE_MAP = :variable_map
        # Role of a captured value whose classification is pending.
        ROLE_CAPTURED_VALUE = :captured_value
        # Role of a value collection.
        ROLE_VALUE_COLLECTION = :value_collection
        # Role of the +fields+ Hash of a value collection.
        ROLE_FIELDS = :fields
        # Role of the +elements+ or +stacktrace+ Array of a value collection.
        ROLE_ELEMENTS = :elements
        # Role of the +entries+ Array of a value collection.
        ROLE_ENTRIES = :entries
        # Role of a key-value pair of an +entries+ Array.
        ROLE_PAIR = :pair

        # For each role whose Hash members have roles by name, the member
        # names and the role of the first member matching each name.
        MEMBER_ROLES = {
          ROLE_ROOT => {"debugger" => ROLE_DEBUGGER}.freeze,
          ROLE_DEBUGGER => {"snapshot" => ROLE_SNAPSHOT}.freeze,
          ROLE_SNAPSHOT => {"captures" => ROLE_CAPTURES}.freeze,
          ROLE_CAPTURES => {
            "entry" => ROLE_CAPTURE_SET,
            "return" => ROLE_CAPTURE_SET,
            "lines" => ROLE_LINES,
          }.freeze,
          ROLE_CAPTURE_SET => {
            "arguments" => ROLE_VARIABLE_MAP,
            "locals" => ROLE_VARIABLE_MAP,
            "captureExpressions" => ROLE_VARIABLE_MAP,
            "throwable" => ROLE_CAPTURED_VALUE,
          }.freeze,
        }.freeze

        # Member names that classify a captured-value Hash.
        CLASSIFICATION_MEMBERS = {
          "value" => true,
          "fields" => true,
          "elements" => true,
          "entries" => true,
          "stacktrace" => true,
          "notCapturedReason" => true,
          "size" => true,
        }.freeze

        # The element members of a value collection in precedence order,
        # with the class their value must have and the role of the
        # container holding the elements.
        ELEMENT_MEMBERS = [
          ["fields", ::Hash, ROLE_FIELDS].freeze,
          ["elements", ::Array, ROLE_ELEMENTS].freeze,
          ["entries", ::Array, ROLE_ENTRIES].freeze,
          ["stacktrace", ::Array, ROLE_ELEMENTS].freeze,
        ].freeze

        # Frame slot: the container node being built.
        FRAME_NODE = 0
        # Frame slot: the member records of a Hash, or the elements of an Array.
        FRAME_ITEMS = 1
        # Frame slot: the position of the next item to build.
        FRAME_CURSOR = 2
        # Frame slot: the role of the container.
        FRAME_ROLE = 3
        # Frame slot: the depth of the captured values among the items.
        FRAME_DEPTH = 4
        # Frame slot: the position of the first member matching each
        # name that has a role, or nil.
        FRAME_FIRST_MEMBERS = 5
        # Frame slot: the registration data of a collection, or nil.
        FRAME_COLLECTION = 6
        # Frame slot: the registration data of the collection whose
        # elements are the items, or nil.
        FRAME_ELEMENT_OWNER = 7
        # Frame slot: the position of a value collection's element member.
        FRAME_ELEMENT_INDEX = 8

        # Initializes the builder of one payload's tree.
        def initialize
          @member_name_json = MEMBER_NAME_JSON.dup
          @type_json = {}
          @next_ordinal = 0
          @step1_candidates = []
          @step2_candidates = []
          @collections = []
        end

        # Builds the encoded tree of +snapshot+.
        #
        # @param snapshot [Hash] the snapshot payload
        # @return [Array(ObjectNode, Array<Prunable>, Array<Prunable>, Array<Prunable>)]
        #   the root node; the primitives over +PRIMITIVE_SIZE_LIMIT+ bytes;
        #   the collections with more than +KEPT_ELEMENT_COUNT+ elements;
        #   all collections
        # @raise [ArgumentError] when +snapshot+ is not a Hash
        # @raise [TypeError] when a key's +to_s+ returns something other than a String,
        #   and for the values JSON.dump raises TypeError for
        # @raise [JSON::GeneratorError, EncodingError] for the strings JSON.dump cannot encode
        def build(snapshot)
          unless ::Hash === snapshot
            raise ArgumentError, "snapshot payload must be a Hash: #{snapshot.class}"
          end

          root = ObjectNode.new
          first_members = {}
          records = hash_records(snapshot, tracked_names: MEMBER_ROLES[ROLE_ROOT], first_members: first_members)
          stack = [[root, records, 0, ROLE_ROOT, 0, first_members, nil, nil, nil]] #: Array[Array[untyped]]
          until stack.empty?
            frame = stack.last #: Array[untyped]
            if frame[FRAME_CURSOR] == frame[FRAME_ITEMS].length
              stack.pop
              complete_frame(frame, stack.last)
            else
              build_item(frame, stack)
            end
          end
          [root, step1_candidates, step2_candidates, collections]
        end

        private

        # The per-payload member-name encodings, preloaded from
        # +MEMBER_NAME_JSON+.
        # @return [Hash{String => String}]
        attr_reader :member_name_json

        # The per-payload encodings of exactly-String and exactly-Symbol
        # +type+ values.
        # @return [Hash{String, Symbol => String}]
        attr_reader :type_json

        # The ordinal the next captured value or collection receives.
        # @return [Integer]
        attr_reader :next_ordinal

        # The primitives larger than +PRIMITIVE_SIZE_LIMIT+ bytes.
        # @return [Array<Prunable>]
        attr_reader :step1_candidates

        # The collections with more than +KEPT_ELEMENT_COUNT+ elements.
        # @return [Array<Prunable>]
        attr_reader :step2_candidates

        # All collections.
        # @return [Array<Prunable>]
        attr_reader :collections

        # Builds the item at the frame's cursor: adds it to the frame's
        # node when it is a leaf, or pushes the frame of its container.
        #
        # @param frame [Array] the frame of the container holding the item
        # @param stack [Array<Array>] the pending frames
        # @return [void]
        def build_item(frame, stack)
          cursor = frame[FRAME_CURSOR]
          if ObjectNode === frame[FRAME_NODE]
            record = frame[FRAME_ITEMS][cursor]
            name = record[0]
            value = record[2]
          else
            name = nil
            value = frame[FRAME_ITEMS][cursor]
          end

          element_owner = frame[FRAME_ELEMENT_OWNER]
          if element_owner && cursor == KEPT_ELEMENT_COUNT
            element_owner[:cut_start_ordinal] = next_ordinal
          end

          case frame[FRAME_ROLE]
          when ROLE_ENVELOPE
            build_envelope_value(frame, name, value, stack)
          when ROLE_VARIABLE_MAP, ROLE_FIELDS, ROLE_ELEMENTS, ROLE_PAIR
            build_captured_value(frame, name, value, frame[FRAME_DEPTH], stack)
          when ROLE_ENTRIES
            build_entry(frame, value, stack)
          when ROLE_LINES
            if ::Hash === value
              push_capture_set(value, stack)
            else
              build_envelope_value(frame, name, value, stack)
            end
          when ROLE_VALUE_COLLECTION
            if cursor == frame[FRAME_ELEMENT_INDEX]
              push_element_container(frame, value, stack)
            else
              build_envelope_value(frame, name, value, stack)
            end
          else
            build_named_member(frame, name, value, stack)
          end
        end

        # Builds a member of a Hash whose members have roles by name: the
        # payload, +debugger+, +debugger.snapshot+, +captures+ or a capture
        # set.
        #
        # @param frame [Array] the frame of the Hash
        # @param name [String] the member name
        # @param value [Object] the member value
        # @param stack [Array<Array>] the pending frames
        # @return [void]
        def build_named_member(frame, name, value, stack)
          member_role = if frame[FRAME_FIRST_MEMBERS][name] == frame[FRAME_CURSOR]
            MEMBER_ROLES.fetch(frame[FRAME_ROLE])[name]
          end

          case member_role
          when ROLE_CAPTURED_VALUE
            # The throwable member of a capture set.
            if value.nil?
              build_envelope_value(frame, name, value, stack)
            else
              build_captured_value(frame, name, value, frame[FRAME_DEPTH], stack)
            end
          when nil
            build_envelope_value(frame, name, value, stack)
          else
            if !(::Hash === value)
              build_envelope_value(frame, name, value, stack)
            elsif member_role == ROLE_CAPTURE_SET
              push_capture_set(value, stack)
            elsif member_role == ROLE_VARIABLE_MAP
              push_variable_map(value, stack)
            else
              first_members = {}
              records = hash_records(value, tracked_names: MEMBER_ROLES[member_role], first_members: first_members)
              stack << [ObjectNode.new, records, 0, member_role, 0, first_members, nil, nil, nil]
            end
          end
          nil
        end

        # Builds a value of the required envelope: a container node for a
        # Hash or an Array, a fragment node for a scalar.
        #
        # @param frame [Array] the frame of the container holding the value
        # @param name [String, nil] the member name, or nil for an Array element
        # @param value [Object] the value
        # @param stack [Array<Array>] the pending frames
        # @return [void]
        def build_envelope_value(frame, name, value, stack)
          if ::Hash === value
            stack << [ObjectNode.new, hash_records(value), 0, ROLE_ENVELOPE, 0, nil, nil, nil, nil]
          elsif ::Array === value
            stack << [ArrayNode.new, array_items(value), 0, ROLE_ENVELOPE, 0, nil, nil, nil, nil]
          else
            add_to_frame(frame, FragmentNode.new(encode_member_value(name, value)))
          end
          nil
        end

        # Pushes the frame of a capture set.
        #
        # @param capture_set [Hash] the capture set
        # @param stack [Array<Array>] the pending frames
        # @return [void]
        def push_capture_set(capture_set, stack)
          ordinal = reserve_ordinal
          first_members = {}
          records = hash_records(capture_set, tracked_names: MEMBER_ROLES[ROLE_CAPTURE_SET], first_members: first_members)
          registration = collection_registration(depth: 0, ordinal: ordinal, element_count: records.length)
          stack << [ObjectNode.new, records, 0, ROLE_CAPTURE_SET, 1, first_members, registration, nil, nil]
          nil
        end

        # Pushes the frame of a variable map.
        #
        # @param variable_map [Hash] the variable map
        # @param stack [Array<Array>] the pending frames
        # @return [void]
        def push_variable_map(variable_map, stack)
          ordinal = reserve_ordinal
          records = hash_records(variable_map)
          node = ObjectNode.new
          registration = collection_registration(depth: 1, ordinal: ordinal, element_count: records.length)
          registration[:element_container] = node
          stack << [node, records, 0, ROLE_VARIABLE_MAP, 2, nil, registration, registration, nil]
          nil
        end

        # Builds an element of an +entries+ Array: a pair for a
        # two-element Array, otherwise a captured value.
        #
        # @param frame [Array] the frame of the +entries+ Array
        # @param value [Object] the element
        # @param stack [Array<Array>] the pending frames
        # @return [void]
        def build_entry(frame, value, stack)
          if ::Array === value
            items = array_items(value)
            if items.length == PAIR_LENGTH
              stack << [ArrayNode.new, items, 0, ROLE_PAIR, frame[FRAME_DEPTH], nil, nil, nil, nil]
            else
              ordinal = reserve_ordinal
              add_primitive(frame, assemble_composite(items, false), frame[FRAME_DEPTH], ordinal)
            end
          else
            build_captured_value(frame, nil, value, frame[FRAME_DEPTH], stack)
          end
          nil
        end

        # Builds a captured value: pushes the frame of a value collection,
        # or adds the fragment node of a primitive.
        #
        # @param frame [Array] the frame of the container holding the value
        # @param name [String, nil] the member name, or nil for an Array element
        # @param value [Object] the captured value
        # @param depth [Integer] the number of collections enclosing the value
        # @param stack [Array<Array>] the pending frames
        # @return [void]
        def build_captured_value(frame, name, value, depth, stack)
          ordinal = reserve_ordinal
          if ::Hash === value
            first_members = {}
            records = hash_records(value, tracked_names: CLASSIFICATION_MEMBERS, first_members: first_members)
            element_index, element_member, element_role = element_member_of(records, first_members)
            if element_index
              reason_index = first_members["notCapturedReason"]
              registration = collection_registration(depth: depth, ordinal: ordinal, element_count: 0)
              registration[:element_member] = element_member
              registration[:element_role] = element_role
              registration[:reason_member_index] = reason_index
              registration[:not_captured_reason] = records[reason_index][2].to_s if reason_index
              registration[:size_member_index] = first_members["size"]
              stack << [ObjectNode.new, records, 0, ROLE_VALUE_COLLECTION, depth, nil, registration, nil, element_index]
            else
              add_primitive(frame, assemble_composite(records, true), depth, ordinal)
            end
          elsif ::Array === value
            add_primitive(frame, assemble_composite(array_items(value), false), depth, ordinal)
          else
            add_primitive(frame, encode_member_value(name, value), depth, ordinal)
          end
          nil
        end

        # Returns the element member of a captured-value Hash: the first of
        # +fields+, +elements+, +entries+ and +stacktrace+, in that order,
        # whose first matching member holds a value of the required class,
        # unless the Hash has a +value+ member.
        #
        # @param records [Array<Array(String, String, Object)>] the Hash's member records
        # @param first_members [Hash{String => Integer}] the position of the first member matching each name
        # @return [Array(Integer, String, Symbol), Array(nil, nil, nil)] the element member's position,
        #   name and container role, or nils for a primitive
        def element_member_of(records, first_members)
          return [nil, nil, nil] if first_members.key?("value")

          ELEMENT_MEMBERS.each do |(member, member_class, role)|
            index = first_members[member]
            if index && member_class === records[index][2]
              return [index, member, role]
            end
          end
          [nil, nil, nil]
        end

        # Pushes the frame of the node holding a value collection's
        # elements.
        #
        # @param frame [Array] the frame of the value collection
        # @param value [Hash, Array] the element member's value
        # @param stack [Array<Array>] the pending frames
        # @return [void]
        def push_element_container(frame, value, stack)
          registration = frame[FRAME_COLLECTION]
          role = registration[:element_role]
          if role == ROLE_FIELDS
            items = hash_records(value)
            node = ObjectNode.new
          else
            items = array_items(value)
            node = ArrayNode.new
          end
          registration[:element_container] = node
          registration[:element_count] = items.length
          stack << [node, items, 0, role, frame[FRAME_DEPTH] + 1, nil, nil, registration, nil]
          nil
        end

        # Adds the fragment node of a primitive to the frame's node and
        # registers it when it is larger than +PRIMITIVE_SIZE_LIMIT+ bytes.
        #
        # @param frame [Array] the frame of the container holding the primitive
        # @param fragment [String] the primitive's JSON text
        # @param depth [Integer] the number of collections enclosing the primitive
        # @param ordinal [Integer] the primitive's ordinal
        # @return [void]
        def add_primitive(frame, fragment, depth, ordinal)
          node = FragmentNode.new(fragment)
          if node.size > PRIMITIVE_SIZE_LIMIT
            step1_candidates << Prunable.new(
              node: node, parent: frame[FRAME_NODE], index: frame[FRAME_CURSOR],
              kind: Prunable::KIND_PRIMITIVE, depth: depth, ordinal: ordinal, last_ordinal: ordinal,
              element_member: nil, element_container: nil, element_count: 0,
              cut_start_ordinal: nil, not_captured_reason: nil,
              reason_member_index: nil, size_member_index: nil,
            )
          end
          add_to_frame(frame, node)
        end

        # Returns the registration data of a collection whose frame is
        # being pushed.
        #
        # @param depth [Integer] the number of collections enclosing the collection
        # @param ordinal [Integer] the collection's ordinal
        # @param element_count [Integer] the number of elements
        # @return [Hash{Symbol => Object}]
        def collection_registration(depth:, ordinal:, element_count:)
          {
            depth: depth,
            ordinal: ordinal,
            element_member: nil,
            element_role: nil,
            element_container: nil,
            element_count: element_count,
            cut_start_ordinal: nil,
            not_captured_reason: nil,
            reason_member_index: nil,
            size_member_index: nil,
          }
        end

        # Finishes a frame whose items are built: registers its collection
        # and adds its node to the parent frame's node.
        #
        # @param frame [Array] the finished frame
        # @param parent_frame [Array, nil] the frame of the container holding the node, nil for the root
        # @return [void]
        def complete_frame(frame, parent_frame)
          return unless parent_frame

          node = frame[FRAME_NODE]
          registration = frame[FRAME_COLLECTION]
          if registration
            collection = Prunable.new(
              node: node, parent: parent_frame[FRAME_NODE], index: parent_frame[FRAME_CURSOR],
              kind: Prunable::KIND_COLLECTION, depth: registration[:depth],
              ordinal: registration[:ordinal], last_ordinal: next_ordinal - 1,
              element_member: registration[:element_member],
              element_container: registration[:element_container],
              element_count: registration[:element_count],
              cut_start_ordinal: registration[:cut_start_ordinal],
              not_captured_reason: registration[:not_captured_reason],
              reason_member_index: registration[:reason_member_index],
              size_member_index: registration[:size_member_index],
            )
            collections << collection
            step2_candidates << collection if collection.cut_start_ordinal
          end
          add_to_frame(parent_frame, node)
        end

        # Adds a built node to the frame's node at the frame's cursor and
        # advances the cursor.
        #
        # @param frame [Array] the frame of the container
        # @param node [Node] the built node
        # @return [void]
        def add_to_frame(frame, node)
          container = frame[FRAME_NODE]
          cursor = frame[FRAME_CURSOR]
          if ObjectNode === container
            record = frame[FRAME_ITEMS][cursor]
            container.add_member(record[0], record[1], node)
          else
            container.add_element(node)
          end
          frame[FRAME_CURSOR] = cursor + 1
          nil
        end

        # Reserves the next ordinal in document order.
        #
        # @return [Integer] the reserved ordinal
        def reserve_ordinal
          ordinal = next_ordinal
          @next_ordinal = ordinal + 1
          ordinal
        end

        # Iterates +hash+ once and returns its member records, encoding
        # every member name.
        #
        # @param hash [Hash] the Hash to iterate
        # @param tracked_names [Hash{String => Object}, nil] the names whose first member position is recorded
        # @param first_members [Hash{String => Integer}, nil] receives the position of the first member matching each tracked name
        # @return [Array<Array(String, String, Object)>] the name, the name's JSON encoding and the value of each member
        def hash_records(hash, tracked_names: nil, first_members: nil)
          records = []
          HASH_EACH_PAIR.bind(hash).call do |key, value|
            name = key.to_s
            name_json = encode_member_name(key, name)
            if tracked_names && first_members && tracked_names.key?(name) && !first_members.key?(name)
              first_members[name] = records.length
            end
            records << [name, name_json, value]
          end
          records
        end

        # Iterates +array+ once and returns its elements.
        #
        # @param array [Array] the Array to iterate
        # @return [Array<Object>]
        def array_items(array)
          items = []
          ARRAY_EACH.bind(array).call { |item| items << item }
          items
        end

        # Returns the JSON text of a Hash or Array from its member records
        # or elements, encoding every nested scalar and member name. The
        # walk keeps nested Hashes and Arrays on an explicit stack.
        #
        # @param items [Array] the member records of a Hash, or the elements of an Array
        # @param hash [Boolean] whether +items+ are member records
        # @return [String]
        def assemble_composite(items, hash)
          buffer = String.new(encoding: ::Encoding::UTF_8)
          buffer << (hash ? "{" : "[")
          stack = [[items, 0, hash]] #: Array[Array[untyped]]
          until stack.empty?
            frame = stack.last #: Array[untyped]
            frame_items = frame[0]
            index = frame[1]
            if index == frame_items.length
              buffer << (frame[2] ? "}" : "]")
              stack.pop
              next
            end

            frame[1] = index + 1
            buffer << "," if index > 0
            if frame[2]
              record = frame_items[index]
              name = record[0]
              buffer << record[1] << ":"
              value = record[2]
            else
              name = nil
              value = frame_items[index]
            end

            if ::Hash === value
              buffer << "{"
              stack << [hash_records(value), 0, true]
            elsif ::Array === value
              buffer << "["
              stack << [array_items(value), 0, false]
            else
              buffer << encode_member_value(name, value)
            end
          end
          buffer
        end

        # Returns the JSON encoding of a member name.
        #
        # @param key [Object] the Hash key
        # @param name [Object] the key's +to_s+
        # @return [String]
        # @raise [TypeError] when +name+ is not a String
        def encode_member_name(key, name)
          unless String === name
            raise TypeError, "#{key.class}#to_s returned #{name.class}, expected String"
          end

          if name.instance_of?(String)
            member_name_json[name] ||= JSON.dump(name).freeze
          else
            JSON.dump(name)
          end
        end

        # Returns the JSON encoding of a scalar member value, taking an
        # exactly-String or exactly-Symbol +type+ value from the
        # per-payload table.
        #
        # @param name [String, nil] the member name, or nil for an Array element
        # @param value [Object] the scalar
        # @return [String]
        def encode_member_value(name, value)
          if name == TYPE_MEMBER &&
              (Symbol === value || (String === value && value.instance_of?(String)))
            type_json[value] ||= JSON.dump(value).freeze
          else
            encode_scalar(value)
          end
        end

        # Returns the JSON encoding of a value that is neither a Hash nor an
        # Array.
        #
        # json 2.6 through 2.x encode a BINARY string that is valid UTF-8 (from
        # custom serializer output, an exception message or a rendered log
        # message); older json raises Encoding::UndefinedConversionError, as it
        # does for the whole payload.
        #
        # @param value [Object] the scalar
        # @return [String]
        def encode_scalar(value)
          if Integer === value
            value.to_s
          elsif true.equal?(value)
            TRUE_JSON
          elsif false.equal?(value)
            FALSE_JSON
          elsif nil.equal?(value)
            NULL_JSON
          else
            JSON.dump(value)
          end
        end
      end
    end
  end
end
