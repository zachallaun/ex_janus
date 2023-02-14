defmodule Janus do
  @moduledoc """
  Authorization superpowers for applications using `Ecto`.

  Priorities:

    * Single source of truth - The same rules that authorize loaded data
      should be able to load authorized data.

    * Authentication-agnostic - Janus should not care about how users
      are modeled or authenticated.

    * Minimal library footprint - Expose a small but flexible API that
      can be used to create an optimal authorization interface for each
      application.

    * Escape hatches where necessary - Complex authorization rules and
      use-cases should be representable when Janus neglects to provide a
      short cut.

  Janus is split into two behaviours:

    * `Janus.Policy` - Defines a policy module. Policy modules are
      responsible for constructing a `%Janus.Policy{}` struct for the
      individual actors of your system. These data structures contain
      the authorization rules for an actor and are used by an
      authorization module to enforce those rules.

    * `Janus.Authorization` - Defines an authorization module.
      Authorization modules expose an API for authorizing and loading
      resources to the rest of your application.

  See those modules for documentation on defining policies and using the
  authorization API.

  ## Quick start

  Janus ships with a Mix task that will generate an authorization and
  policy module for you:

  ```bash
  $ mix janus.gen.authz
  * creating lib/my_app/authz.ex
  * creating lib/my_app/authz/policy.ex
  ```

  See `Mix.Tasks.Janus.Gen.Authz` for more info.

  ## Installation

  Janus can be installed by adding `ex_janus` to your deps in `mix.exs`:

      defp deps do
        [
          {:ex_janus, "~> #{Janus.MixProject.version()}"}
        ]
      end

  ## Integration with `Ecto.Query`

  The primary assumption that Janus makes is that your resources are
  backed by an `Ecto.Schema`. Using Ecto's schema reflection
  capabilities, Janus is able to use the same policy to authorize a
  single resource and to construct a composable Ecto query that is aware
  of field types and associations.

      # This query would result in the 5 latest posts that the current
      # user is authorized to see, preloaded with the user # who made
      # the post (but only if the current user is  allowed to see that
      # user).

      Post
      |> MyApp.Authz.scope(:read, current_user,
        preload_authorized: :user
      )
      |> order_by(desc: :inserted_at)
      |> limit(5)

  This integration with Ecto queries is main reason Janus exists.

  ## Why (not) Janus?

  Janus was created to scratch an itch: the same rules that authorize
  loaded data should be able to load authorized data. In concrete terms,
  a rule that defines whether a user can edit a resource should also be
  able to load all the resources that user can edit.

  Loading data this way should be:

    1. efficient - loading everything and then filtering it in-memory
       doesn't cut it;

    2. composable - it should be possible to add additional conditions
       when loading data;

    3. ergonomic - authorization should slot-in naturally without major
       rewrites.

  Thankfully, integration with `Ecto.Query` solves for all of the above.
  One only needs authorization rules that can be translated into a
  query.

  And thus, Janus was born.

  ### Janus may be a good fit if...

    * you're authorizing data backed by `Ecto.Schema`. Janus relies on
      the reflection capabilities of schemas to produce correct queries,
      cast values, navigate associations, etc.

    * you share interfaces between users with different permissions.
      Janus allows you to scope queries in a uniform way using the
      current user (or lack of one), making shared interfaces a natural
      default.

    * you prefer to have the final say. Janus takes an approach similar
      to Phoenix, generating code that supports certain conventions
      while allowing you to override or redefine behavior to fit your
      preferences.

    * you prefer a functional API for defining rules. Authorization
      policies are data; adding an authorization rule just transforms
      that data. Policies can be built using the full extent and natural
      composability of the Elixir language.

  ### Janus may not be a good fit if...

    * you're only authorizing actions that don't have an obvious
      association to data backed by `Ecto.Schema`. For instance, a
      `:send_welcome_email` action without some kind of `Email` schema.
      Janus does, however, give you a natural place to define that sort
      of API yourself (your policy module).

    * you want an easy-to-read DSL for authorization rules. Janus
      policies are "just code", so readability will depend on your own
      style and structure. If you value readability/scannability very
      highly, definitely check out [`LetMe`](https://hexdocs.pm/let_me),
      which provides a great DSL and makes some different trade-offs
      than Janus does.

    * you want runtime introspection for your authorization rules, like
      a list of all actions a user can perform. Janus does not currently
      provide structured access to this information, but you might again
      turn to [`LetMe`](https://hexdocs.pm/let_me), which provides
      introspection capabilities.
  """

  @type action :: any()
  @type schema_module :: module()
  @type actor :: any()
end
