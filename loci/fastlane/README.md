fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## iOS

### ios lint

```sh
[bundle exec] fastlane ios lint
```

Run SwiftLint check

### ios test

```sh
[bundle exec] fastlane ios test
```

Run unit test suite

### ios beta

```sh
[bundle exec] fastlane ios beta
```

Build Beta config (com.fernandocorreia.loci.beta) and upload to TestFlight

### ios seed_signing

```sh
[bundle exec] fastlane ios seed_signing
```

One-time: create signing certs/profiles and push them to the match repo

### ios release

```sh
[bundle exec] fastlane ios release
```

Release to the App Store (phased rollout)

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
