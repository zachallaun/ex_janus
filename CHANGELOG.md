# Changelog

This project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## Unreleased

This release updates the recommended usage of `Janus` to encourage a separate Policy and Authorization (Authz) module.
An Authz module, created with `use Janus.Authorization`, provides the API that the rest of your application uses to enforce authorization.
A Policy module, created with `use Janus.Policy`, is concerned only with defining authorization rules and is generally only referenced from an Authz module.

### Enhancements

  * [**Breaking** / Janus] Remove `use Janus`, which defined a single authorization/policy module, in favor of `use Janus.Policy` and `use Janus.Authorization`.
  * [Janus.Authorization] Add `use Janus.Authorization`.
  * [mix janus.gen.authz] Replaces `mix janus.gen.policy` and now generates both a `MyApp.Authz` and a `MyApp.Authz.Policy` module.

## v0.3

See CHANGELOG.md in the [v0.3 branch](https://github.com/zachallaun/ex_janus/blob/v0.3/CHANGELOG.md).
