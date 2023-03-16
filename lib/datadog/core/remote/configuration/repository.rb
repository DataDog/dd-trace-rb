# frozen_string_literal: true

require_relative 'content'

module Datadog
  module Core
    module Remote
      class Configuration
        # Repository
        class Repository
          attr_reader \
            :contents,
            :opaque_backend_state,
            :root_version,
            :targets_version

          UNVERIFIED_ROOT_VERSION = 1
          INITIAL_TARGETS_VERSION = 0

          def initialize
            @contents = ContentList.new
            @opaque_backend_state = nil
            @root_version = UNVERIFIED_ROOT_VERSION
            @targets_version = INITIAL_TARGETS_VERSION
          end

          def paths
            @contents.paths
          end

          def [](path)
            @contents[path]
          end

          def transaction
            transaction = Transaction.new

            yield(self, transaction)

            commit(transaction)
          end

          def commit(transaction)
            transaction.operations.each { |op| op.apply(self) }
          end

          def state
            State.new(self)
          end

          # State store the repository state
          class State
            attr_reader \
              :root_version,
              :targets_version,
              :config_states,
              :has_error,
              :error,
              :opaque_backend_state

            def initialize(repository)
              @root_version = repository.root_version
              @targets_version = repository.targets_version
              @config_states = []
              @has_error = false
              @error = ''
              @opaque_backend_state = repository.opaque_backend_state
            end
          end

          # Encapsulates transaction operations
          class Transaction
            attr_reader :operations

            def initialize
              @operations = []
            end

            def delete(path)
              @operations << Operation::Delete.new(path)
            end

            def insert(path, target, content)
              @operations << Operation::Insert.new(path, target, content)
            end

            def update(path, target, content)
              @operations << Operation::Update.new(path, target, content)
            end

            def set(**options)
              @operations << Operation::Set.new(**options)
            end
          end

          # Operation
          module Operation
            # Base
            class Base
              def apply(repository)
                raise NoMethodError
              end
            end

            # Delete contents base on path
            class Delete < Base
              attr_reader :path

              def initialize(path)
                super()
                @path = path
              end

              def apply(repository)
                repository.contents.reject! { |c| c.path.eql?(@path) }
              end
            end

            # Insert content into the reporistory contents
            class Insert < Base
              attr_reader :path, :target, :content

              def initialize(path, target, content)
                super()
                @path = path
                @target = target
                @content = content
              end

              def apply(repository)
                repository.contents << @content if repository[path].nil?
              end
            end

            # Update existimng repository's contents
            class Update < Base
              attr_reader :path, :target, :content

              def initialize(path, target, content)
                super()
                @path = path
                @target = target
                @content = content
              end

              def apply(repository)
                repository.contents.map! { |c| c.path.eql?(@path) ? @content : c }
              end
            end

            # Set repository metadata
            class Set < Base
              attr_reader :opaque_backend_state, :targets_version

              def initialize(**options)
                super()
                @opaque_backend_state = options[:opaque_backend_state]
                @targets_version = options[:targets_version]
              end

              def apply(repository)
                repository.instance_variable_set(:@opaque_backend_state, @opaque_backend_state) if @opaque_backend_state

                repository.instance_variable_set(:@targets_version, @targets_version) if @targets_version
              end
            end
          end

          private_constant :Operation
        end
      end
    end
  end
end
