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

  Janus is split into two primary components:

    * `Janus.Policy` - functions and behaviour for defining _policy
    modules_, which describe the allowed actors, actions, and resources
    in your application. This is where you look if you're writing a
    policy module.

    * `Janus.Authorization` - functions and behaviour used by the rest
    of your application to authorize and load resources. This is where
    you look if you're using a policy module.

  Janus defines a Mix task to generate the basic policy module that will
  get you started:

      $ mix janus.gen.policy

  ## Installation

  Janus can be installed by adding `ex_janus` to your deps in `mix.exs`:

      defp deps do
        [
          {:ex_janus, "~> 0.2.1"}
        ]
      end

  ## Policies

  Policy modules are created by invoking `use Janus`, which implements
  both the `Janus.Policy` and `Janus.Authorization` behaviours:

      defmodule Policy do
        use Janus

        @impl true
        def build_policy(policy, _user) do
          policy
        end
      end

  When you invoke `use Janus`, default implementations are injected for
  required callbacks, except for `c:Janus.Policy.build_policy/2`. This
  callback is your foundation, as it returns the authorization policy
  for an individual user of your application.

  The policy above is not very useful (it doesn't allow anyone to do
  anything) but that can be changed by using the `Janus.Policy` API to
  define actions, resources, and conditions that make up your
  authorization rules.

      def build_policy(policy, %User{role: :moderator} = mod) do
        policy
        |> allow(Post, :read)
        |> allow(Post, [:edit, :archive, :unarchive], where: [user: [role: :member]])
        |> allow(Post, [:edit, :archive, :unarchive], where: [user_id: mod.id])
        |> deny(Post, :unarchive, where: [archived_by: [role: :admin]])
      end

  See the `Janus.Policy` documentation for more on defining policies.

  ## Authorization

  With our policy module defined, it can now be used to load and
  authorize resources.

      iex> Policy.authorize(some_post, :archive, moderator)
      {:ok, some_post}

      iex> Policy.authorize(post_archived_by_admin, :unarchive, moderator)
      {:error, :not_authorized}

      iex> Policy.scope(Post, :read, moderator)
      %Ecto.Query{}

      iex> Policy.scope(Post, :read, moderator) |> Repo.all()
      [ ... posts the moderator can read ]

      iex> Policy.any_authorized?(Post, :edit, moderator)
      true # there are rules allowing moderators to edit posts

      iex> Policy.any_authorized?(Post, :delete, moderator)
      false # there are no rules that allow moderators to delete posts

  These functions make up the `Janus.Authorization` behaviour, and their
  definitions were injected by default when we invoked `use Janus`. This
  is the "public API" that the rest of your application will use to
  authorize resources.

  See the `Janus.Authorization` documentation for more.

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
      |> Policy.scope(:read, current_user,
        preload_authorized: :user
      )
      |> order_by(desc: :inserted_at)
      |> limit(5)

  This integration with Ecto queries is main reason Janus exists.

  ## Configuration

  Some defaults can be configured by passing them as options when
  invoking `use Janus`. Those are:

    * `:repo` - `Ecto.Repo` used to load associations when required by
      your authorization rules

    * `:load_associations` - Load associations when required by your
      authorization rules (requires `:repo` config option to be set or
      to be passed explicitly at the call site), defaults to `false`

  For example:

      defmodule MyApp.Policy do
          use Janus,
            repo: MyApp.Repo,
            load_associations: true

          # ...
      end

  These defaults will be referenced in the `Janus.Authorization`
  documentation where they are used.

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

  require Ecto.Query

  @type action :: any()
  @type schema_module :: module()
  @type actor :: any()

  @doc """
  Sets up a module to implement the `Janus.Policy` and
  `Janus.Authorization` behaviours.

  Using `use Janus` does the following:

    * adds the `Janus.Policy` behaviour, imports functions used to
      define the required callback `c:Janus.Policy.build_policy/2`, and
      defines a `build_policy/1` helper

    * adds the `Janus.Authorization` behaviour and injects default
      (overridable) implementations for all callbacks

  ## Options

    * `:load_associations` - Load associations when required by your
      authorization rules (requires `:repo` config option to be set or
      to be passed explicitly at the call site), defaults to `false`

    * `:repo` - `Ecto.Repo` used to load associations when required by
      your authorization rules

  See "Configuration" section for details.

  ## Example

      defmodule MyApp.Policy do
        use Janus, repo: MyApp.Repo

        @impl true
        def build_policy(policy, _actor) do
          policy
          # |> allow(...)
        end
      end
  """
  defmacro __using__(opts \\ []) do
    quote location: :keep do
      @behaviour Janus.Authorization

      use Janus.Policy, unquote(opts)
      require Janus

      @impl Janus.Authorization
      def authorize(resource, action, actor, opts \\ []) do
        Janus.Authorization.authorize(resource, action, build_policy(actor), opts)
      end

      @impl Janus.Authorization
      def any_authorized?(schema, action, actor) do
        Janus.Authorization.any_authorized?(schema, action, build_policy(actor))
      end

      @impl Janus.Authorization
      def scope(query_or_schema, action, actor, opts \\ []) do
        Janus.Authorization.scope(query_or_schema, action, build_policy(actor), opts)
      end

      defoverridable authorize: 4, any_authorized?: 3, scope: 4
    end
  end
end
