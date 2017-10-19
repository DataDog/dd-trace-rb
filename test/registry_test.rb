require 'minitest/autorun'
require 'ddtrace'
require 'ddtrace/registry'

module Datadog
  class RegistryTest < Minitest::Test
    def test_object_retrieval
      registry = Registry.new

      object1 = Object.new
      object2 = Object.new

      registry.add(:object1, object1)
      registry.add(:object2, object2)

      assert_same(object1, registry[:object1])
      assert_same(object2, registry[:object2])
    end

    def test_hash_coercion
      registry = Registry.new

      object1 = Object.new
      object2 = Object.new

      registry.add(:object1, object1, true)
      registry.add(:object2, object2, false)

      assert_equal({ object1: true, object2: false }, registry.to_h)
    end

    def test_enumeration
      registry = Registry.new

      object1 = Object.new
      object2 = Object.new

      registry.add(:object1, object1, true)
      registry.add(:object2, object2, false)

      assert(registry.respond_to?(:each))
      assert_kind_of(Enumerable, registry)

      # Enumerable#map
      objects = registry.map(&:klass)
      assert_kind_of(Array, objects)
      assert_equal(2, objects.size)
      assert_includes(objects, object1)
      assert_includes(objects, object2)
    end

    def test_registry_entry
      entry = Registry::Entry.new(:array, Array, true)

      assert_equal(:array, entry.name)
      assert_equal(Array, entry.klass)
      assert_equal(true, entry.auto_patch)
    end
  end
end
