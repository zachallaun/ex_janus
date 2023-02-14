# Generated Modules

> #### Work in progress {: .warning}
>
> This guide is incomplete, though its contents may still be useful if you're getting started.

Janus defines a small but flexible API that can be used to create a higher-level authorization interface for your application.
To support common conventions, like the use of Phoenix-style context modules, Janus provides a policy generator that defines helpers that are especially useful in those circumstances.

The goal of this guide is to explain the usage of, and reasoning behind, those helpers.

## Generating an authorization and policy module

```bash
$ mix janus.gen.authz
* creating lib/my_app/authz.ex
* creating lib/my_app/authz/policy.ex
```

The generated policy module is extremely minimal, but the `MyApp.Authz` module contains a number of helpers.

## Overview of helpers

Most of the generated helpers are designed to wrap common `Ecto.Repo` CRUD operations in a way that facilitates refactoring existing unauthorized calls to authorized ones with minimal necessary changes.
The helpers don't cover everything, but they cover a large portion of use-cases and provide a pattern for wrapping additional operations if needed.

The following helpers are included in newly-generated policy modules:

* `authorized_fetch_by` - wraps `c:Ecto.Repo.get_by/3`, gets a resource using the given attributes and then authorizes for the given action/user

* `authorized_fetch_all` - wraps `c:Ecto.Repo.all/2`, fetch a list of resources that are authorized for the given action/user

* `authorized_insert` - wraps `c:Ecto.Repo.insert/2`, operates on a changeset, failing with a validation error if the inserted resource would not be authorized for the given action/user

* `authorized_update` - wraps `c:Ecto.Repo.update/2`, operates on a changeset, failing with a validation error if the updated resource would not be authorized for the given action/user either before or after applying changes

* `authorized_delete` - wraps `c:Ecto.Repo.delete/2`, deletes the given resource if it is authorized for the given action/user

* `validate_authorized` - changeset validation that ensures the resource being changed is authorized, adding a validation error otherwise.

We'll go over each of these and how they might be used in the sections that follow.

> #### Note on generated code {: .info}
>
> Remember that generated code is _your_ code!
> It should be modified, replaced, and deleted as you see fit.
>
> Instead of including these helpers in `Janus`, they are generated as a starting point for your application.
> They enable the usage patterns described below, but if they aren't useful to you, toss them and use whatever you see fit!

## Authorized operations

The goal is to transition from unauthorized to authorized operations as smoothly as possible.
`authorized_*` functions take the same arguments as their `Ecto.Repo` counterparts, except that they add additional keyword options related to authorization.

Let's look at some examples.

```elixir
iex> Repo.get_by(Post, id: 12345)
%Post{}

iex> MyApp.Authz.authorized_fetch_by(Post, [id: 12345], authorize: {:read, user})
{:ok, %Post{}}
# or
{:error, :not_authorized}
# or
{:error, :not_found}
```

All of the `authorized_*` functions take the `:authorize` keyword option, which should be either a tuple of `{action, actor}` as above, or `false` to skip authorization altogether.
An `ArgumentError` will be raised if `:authorize` is not present, but this can be changed if you'd prefer authorization to be opt-in instead of opt-out.
(Opt-out, the default, is the recommended approach, though it may require more refactoring work up-front.)

There's another obvious difference in the example above: `authorized_fetch_by/3` returns an `:ok` or `:error` tuple instead of the resource or `nil`.
Returning a tuple allows us to differentiate between a lookup failure and an auth failure.

A similar approach is used in the next example:

```elixir
iex> Repo.all(Post)
[%Post{}, ...]

iex> MyApp.Authz.authorized_fetch_all(Post, authorize: {:read, user})
{:ok, [%Post{}, ...]}
# or
{:error, :not_authorized}
```

A tuple is also returned here to differentiate authorization failures and an empty result.

An Ecto query can also be passed as the first argument.

```elixir
iex> query = from p in Post, where: p.inserted_at > ago(1, "month")

iex> Repo.all(query)
[%Post{}, ...]

iex> MyApp.Authz.authorized_fetch_all(query, authorize: {:read, user})
{:ok, [%Post{}, ...]}
# or
{:error, :not_authorized}
```
