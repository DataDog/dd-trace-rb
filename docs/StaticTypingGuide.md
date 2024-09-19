# Static Typing Guide

Static typing description is achieved via Ruby core [RBS](https://github.com/ruby/rbs).

Static type checking is achieved via [Steep](https://github.com/soutaro/steep).

## Quick start


### Run the type check

```
bundle exec steep check [sources]
```

The `sources` arguments are optional and used to scope type checking to a smaller set of files or directories.

### Generate type signature skeleton

```
bundle exec rbs prototype rb [source files]
```

Outputs `.rbs` content on stdout. The `source files` arguments lists the files from which the skeleton will be statically built from parsing. No evaluation occurs, therefore this has limited typing analysis capability, typically resulting in a lot of `untyped`.

Note: Comments are reproduced as is which is useful for a visual check but should be manually removed when moving the skeleton to a `.rbs` file, because of the duplication and risk of comments getting desynced.

## Layout

Ruby code in `.rb` files are, as is customary for a gem, stored in `lib`.

While RBS type annotations could be put inline, this creates a lot of noise, hampering "pure Ruby" readability. While the closeness with the code itself may look like an advantage, such annotations live in comments, which are harder to read and mix with other comments.

RBS types can be described in any number of `.rbs` files, stored in `sig`. These files can be generated, syntax highlighted, checked, linted, and more. This is therefore the chosen approach.

While the presence of `.rb` and `.rbs` files is entirely decoupled, here we choose to have one `.rbs` file per `.rb` file, mirroring the `lib` structure in `sig`. This has a number of advantages such as tracking typing progress, noticing stale files, generating new files without messing with existing type information, configuring IDEs and editors to jump from source to signature and back...

Tools such as `rbs prototype` output comments. These should be removed, and only comments relevant to typing should end up in `.rbs` files.

## Progressive typing

Similar to many other Ruby tools, Steep reads project configuration from a DSL in `Steepfile`. We will use that to allow progressive typing.

### Type checking vs signature loading

Steep distinguishes between loading signatures and actually checking code for signatures. This is extremely useful to progressively type code, limiting check scope while still being able to provide signatures to code that can't be fully checked yet.

```
target :default do
  signature "sig"           # ALL signatures from this directory will be loaded

  check "lib/foo/bar"       # ONLY this source code folder will be checked against, using ALL signatures above
  ignore "lib/foo/bar/baz"  # EXCEPT this subfolder
end
```

### Dependency signatures

Steep starts with a [minimal core](https://github.com/ruby/rbs/tree/master/core) loaded type signatures. Adding more [types from the Ruby stdlib](https://github.com/ruby/rbs/tree/master/stdlib) should be done progressively as required:

```
  library "set" # adds typing for Ruby stdlib's Set
```

Note: These signatures are part of [`rbs`](), which is included in Ruby releases since Ruby 3.0.

Gems can embed a `sig` directory, which can be used directly:

```
  library "some_gem_with_a_sig_dir"
```

Some gems don't have typing information.

In addition, a [vast collection of gems](https://github.com/ruby/gem_rbs_collection) have been typed. These can be fetched via a Rubygems/Bundler-like feature of RBS called [collections](https://github.com/ruby/rbs/blob/e91be7275f4005b1aeac8eadc2faa2b4ad5fdfef/docs/collection.md)

```
  collection_config "rbs_collection.steep.yaml"
```

This yaml file is akin to a Gemfile, describes the sources and gem signatures to fetch, and also has a lockfile mechanism. It can also integrate with `bundler` to match the signatures with the gem versions in use.

Otherwise signatures can be vendored:

```
  repo_path "vendor/rbs"
  library "subdir"
```

Typically these are be written as needed for gems entirely missing signatures, and ideally contributed back either upstream to the gem project itself or to the gem rbs collection project.

### Measuring progress

With the described layout and 1:1 match, it becomes easy to track coarse-grained coverage, additions, removals, changes through refactorings, in a similar way as is usually done with unit tests or specs.

In addition, to output typing detailed coverage statistics:

```
bundle exec steep stats
```

## Typing a file

### Basics

To type a `.rb` file without a matching `.rbs` file, start with the skeleton:

```
mkdir -p sig/foo
bundle exec rbs prototype rb lib/foo/bar.rb > sig/foo/bar.rbs
```

One can then proceed to [adjusting the signatures](https://github.com/ruby/rbs/blob/e91be7275f4005b1aeac8eadc2faa2b4ad5fdfef/docs/syntax.md) ([by example](https://github.com/ruby/rbs/blob/e91be7275f4005b1aeac8eadc2faa2b4ad5fdfef/docs/rbs_by_example.md)), removing as much `untyped` as possible.

### Type profiling

To discover types, one can leverage [`typeprof`](https://github.com/ruby/typeprof). Contrary to `rbs prototype rb` which relies solely on static parsing, `typeprof` is a Ruby interpreter, except it doesn't *execute* Ruby code, merely evaluates it to track types. Entry point calls to explore the various codepaths are required.

With this file:

```
# test.rb
def foo(x)
  p x        # reveal type of x

  if x > 10
    x.to_s
  else
    nil
  end
end

foo(42)      # this call is needed otherwise there's nothing evaluated!
foo(3)       # make sure to explore as many codepaths as possible to get best coverage
```

The following is evaluated:

```
$ typeprof test.rb
# TypeProf 0.21.2

# Revealed types
#  foo.rb:3 #=> Integer

# Classes
class Object
  private
  def foo: (Integer x) -> String?
end
```

One quick hackish way to type a class is to add a bunch of calls all the way down the file defining that class and run `typeprof` on it exploring the most interesting codepaths. This can also be achieved with a separate file requiring the one we want to type and performing calls there. In theory `typeprof` could be run on unit test files having 100% coverage and output precise type information for the tested code.

See the [demo doc](https://github.com/ruby/typeprof/blob/26ab9108860d9a4ce050acb3422ee7721d4d50b0/doc/demo.md) for more examples and features.

## Useful commands

### List stale `.rbs`

```
# check everything
bundle exec rake rbs:stale

# check one file
bundle exec rake rbs:stale[sig/foo/bar.rbs]

# check a directory
bundle exec rake rbs:stale[sig/foo]

# clean stale files and empty directories
bundle exec rake rbs:clean
```

### List missing `.rbs`

```
# check everything
bundle exec rake rbs:missing

# check one file
bundle exec rake rbs:missing[lib/foo/bar.rb]

# check a directory
bundle exec rake rbs:missing[lib/foo]
```

### Generate `.rbs` skeletons

```
# prototype one file if missing
bundle exec rake rbs:prototype[lib/foo/bar.rb]

# prototype one file unconditionally
bundle exec rake rbs:prototype[force,lib/foo/bar.rb]

# prototype missing signatures in a directory
bundle exec rake rbs:prototype[lib/foo]

# prototype all files in a directory
bundle exec rake rbs:prototype[force, lib/foo]

# prototype every missing file
bundle exec rake rbs:prototype

# prototype every file
bundle exec rake rbs:prototype[force]
```
