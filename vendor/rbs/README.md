This directory contains signatures we created for third-party gems that *do not* ship with RBS signatures.

Without these signatures, we have to skip type checking all `dd-trace-rb` code that interacts with these gems, which is not insignificant (e.g. all `contrib`).

# How to add new vendor signatures

1. You only need to add signatures for the parts of the gem that we interact with.
