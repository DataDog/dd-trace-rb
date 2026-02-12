# Libdatadog development

These instructions can quickly get outdated, so feel free to open an issue if they're not working (and/or ping @ivoanjo).

## Using libdatadog builds from CI or GitHub

If you're developing inside docker/natively on Linux, you can use libdatadog builds from CI and GitHub.

Here's what to do:

1. Create a folder for extracting libdatadog into based on your ruby platform (for instance inside the dd-trace-rb repo):

```bash
export DD_RUBY_PLATFORM=`ruby -e 'puts Gem::Platform.local.to_s'`
echo "Current ruby platform: $DD_RUBY_PLATFORM"
mkdir -p my-libdatadog-build/$DD_RUBY_PLATFORM
```

2. Find a libdatadog build from CI or [GitHub releases](https://github.com/DataDog/libdatadog/releases). This should match the Ruby platform seen above.
3. Extract the libdatadog build into the folder:

```bash
# In this example the build is in my downloads; notice the use of strip-components to get the correct folder structure
tar zxvf ~/Downloads/libdatadog-x86_64-unknown-linux-gnu.tar.gz -C my-libdatadog-build/$DD_RUBY_PLATFORM/ --strip-components=1
# Here's how it should look after
ls my-libdatadog-build/$DD_RUBY_PLATFORM
bin  cmake  include  lib  LICENSE  LICENSE-3rdparty.yml  NOTICE
```

4. Tell Ruby where to find libdatadog: ```export LIBDATADOG_VENDOR_OVERRIDE=`pwd`/my-libdatadog-build/``` (Notice no platform + use of pwd for full path here)
5. From dd-trace-rb, run `bundle exec rake clean compile`
6. For incremental builds, usually `bundle exec rake compile` is faster and `clean` is not needed

## Native development in docker/linux

If you want to build libdatadog locally (e.g. to experiment with local changes), you can follow the same instructions as
"Using libdatadog builds from CI or GitHub" BUT replace steps 2 and 3 (where you would download a prebuilt libdatadog from CI)
with:

2. From inside of the libdatadog repo, follow the [instructions to build libdatadog](https://github.com/datadog/libdatadog?tab=readme-ov-file#builder-crate)
   and build libdatadog into the build folder you picked: `cargo run --bin release (...see libdatadog readme for details...) -- --out my-libdatadog-build/$DD_RUBY_PLATFORM`
3. Jump to step 4 of "Using libdatadog builds from CI or GitHub"

## Native development on macOS

For profiling in particular, you'll need to set `export DD_PROFILING_MACOS_TESTING=true` and re-run `bundle exec rake clean compile`
as we don't build/enable profiling on macOS by default.
