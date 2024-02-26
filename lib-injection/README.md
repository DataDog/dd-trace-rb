### Injection

Injection is Datadog's strategy to [instrument application without touching application code](https://docs.datadoghq.com/tracing/trace_collection/library_injection_local/?tab=kubernetes). Currently, This strategy is implemented by adding `datadog` to your application's `Gemfile` to [instrument your application](https://docs.datadoghq.com/tracing/trace_collection/dd_libraries/ruby/#rails-or-hanami-applications)).

* Supports `Ruby on Rails` and `Hanami` application
* Requires [bundler](https://bundler.io/) version 2.3 or above
* Does not support frozen `Gemfile` or vendoring gems ([Bundler's Deployment Mode](https://www.bundler.cn/man/bundle-install.1.html#DEPLOYMENT-MODE) or setting `BUNDLE_PATH`)

Examples:

Bundler vendors gems from a specific location, instead of system default.
```bash
bundle config path vendor/cache
# or
BUNDLE_PATH=vendor/cache bundle install
# or
bundle install --path=vendor/cache
```

Bundler freezes the `Gemfile` to prevent the `Gemfile.lock` to be updated after this install.
```bash
bundle config set frozen true
# or
bundle install --frozen
```

[Bundler's Deployment Mode](https://www.bundler.cn/man/bundle-install.1.html#DEPLOYMENT-MODE) would freeze the `Gemfile` and vendor gems from `vendor/cache`.

```bash
bundle config set deployment true
# or
bundle install --deployment
```


### Packaging

There's an internal gitlab build pipeline ships pre-installed `datadog` deb and rpm packages.

Currently, we support

| Environment| version |
|---|---|
| Ruby  | `2.7`, `3.0`, `3.1`, `3.2`|
| Arch  | `amd64`, `arm64` |
| glibc |  2.28+ |

In order to ship `datadog` and its dependencies as a pre-install package, we need a few tweaks in our build pipeline.

* Use multiple custom built Ruby images to build native extensions. Those images are based on Debian `buster` to support older distribution and Ruby is compiled as a static library with `--disable-shared` option which disables the creation of shared libraries (also known as dynamic libraries or DLLs).
* Install `ffi` gem with its built-in `libffi` native extension instead of using system's `libffi`.
* After gem installation, the native extensions would be store in `extensions/x86_64-linux/3.2.0-static/`(see `Gem.extension_api_version`). We symlink those directories to remove the `-static` suffix so user’s ruby can detect those  `.so` files and make sure files have read permission.
