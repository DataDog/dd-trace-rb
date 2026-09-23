# Verifying gem build provenance

Each release of the `datadog` gem since 2.13.0 is signed at publish time. The signature proves that the `.gem` file you downloaded was published by the release workflow of this repository. It does not prove that the code inside the gem is free of defects.

## What is signed

When the [publish workflow](../.github/workflows/publish.yml) pushes a new gem version to RubyGems.org, it signs the `.gem` file with a keyless [Sigstore](https://docs.sigstore.dev) signature. The signing key is short-lived and is bound to the GitHub Actions identity of the workflow. The signature therefore records the repository, the workflow, the branch, and the commit that published the gem.

RubyGems.org stores the signature bundle for each gem version and serves it through its API. The signature is also recorded in the public [Rekor transparency log](https://search.sigstore.dev), where anyone can inspect it.

The `.gem` files attached to the [GitHub releases](https://github.com/DataDog/dd-trace-rb/releases) are downloaded from RubyGems.org, so they carry the same bytes and the same signature.

## How to check a gem

You need a current release of [cosign](https://github.com/sigstore/cosign).

1. Download the gem version you want to check:

   ```sh
   VERSION=2.42.0
   gem fetch datadog -v "$VERSION"
   ```

2. Download the signature bundle from RubyGems.org:

   ```sh
   curl -s "https://rubygems.org/api/v1/attestations/datadog-${VERSION}.json" | jq '.[0]' > bundle.json
   ```

3. Check the gem against the bundle:

   ```sh
   cosign verify-blob "datadog-${VERSION}.gem" \
     --bundle bundle.json \
     --certificate-oidc-issuer "https://token.actions.githubusercontent.com" \
     --certificate-identity-regexp "^https://github\.com/DataDog/dd-trace-rb/\.github/workflows/publish\.yml"
   ```

If the gem is authentic, cosign prints `Verified OK`.

The two `--certificate-*` flags are your trust policy. The first says that the signer must be GitHub Actions. The second says that the signer must be the publish workflow of this repository. If you drop these flags, cosign only checks the signature math and accepts any publisher.

## What is not covered

- If you build the gem from source, the resulting file is not signed by this process.
- The container images published by this repository are built by GitLab CI. They are not covered by the RubyGems.org signature.
- The signature covers the publish step, which builds and pushes the gem in one workflow job. It does not attest the results of the tests that ran before the publish.
