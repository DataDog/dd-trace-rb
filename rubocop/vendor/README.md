# Standard rules for RuboCop

RuboCop loads these upstream files directly, without the Standard gems or CLI.
Keep them unchanged; project overrides belong in the root `.rubocop.yml`.
Each directory includes its upstream MIT licence.

| Directory | Upstream release | Files |
| --- | --- | --- |
| `standard` | [1.49.0](https://github.com/standardrb/standard/tree/v1.49.0) | `config/base.yml` |
| `standard-custom` | [1.0.2](https://github.com/standardrb/standard-custom/tree/v1.0.2) | `config/base.yml`, `lib/standard/cop/block_single_line_braces.rb` |
| `standard-performance` | [1.9.0](https://github.com/standardrb/standard-performance/tree/v1.9.0) | `config/base.yml` |

The engine dependencies remain RuboCop `~> 1.75.2` and rubocop-performance
`~> 1.26.0`. The initial import preserves the previously inherited base configs,
including disabled cops and autocorrection settings. It does not add Standard's
Ruby-version-specific configuration layers. The root config targets Ruby 2.5.

## Updating

1. Choose upstream releases and check their gemspecs for compatible engine versions.
2. Replace the files above and their licences from those release tags. Inspect
   upstream loaders for added cops, configuration layers, or changed dependencies.
3. Update this provenance, `LICENSE-3rdparty.csv`, and the engine pins in the
   hand-maintained runtime gemfiles if needed. Regenerate affected lockfiles with Bundler.
4. Compare `bundle exec rubocop --show-cops` before and after the update. Review
   enabled cops, options, and file-selection changes, not just reported offences.
5. Run `bundle exec rake rubocop test:custom_cop` and review autocorrections before
   applying them across the repository.

Use `rubocop:disable`, `rubocop:enable`, and `rubocop:todo` for inline exceptions.
Standard's compatibility patches, CLI, plugins, and language server are not vendored.
