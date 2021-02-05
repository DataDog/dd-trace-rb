require 'spec/support/thread_helpers'

# Ethon will lazily initialize LibCurl,
# which spans a leaky native thread.
#
# LibCurl is normally first initialized when
# a new instance of Ethon::Easy is created.
# We tag the newly created thread in the :ethon
# group to allow for later reporting.
#
# This tagging allows us to still ensure that the integration
# itself is leak-free.
def ethon_easy_new(*args)
  ThreadHelpers.with_leaky_thread_creation(:ethon) do
    Ethon::Easy.new(*args)
  end
end
