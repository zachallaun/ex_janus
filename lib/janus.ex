defmodule Janus do
  @moduledoc """
  Authorization superpowers for your `Ecto` schemas.

  Janus prioritizes:

    * Single source of truth: authorization rules should be defined once
      and used for authorizing individual actions as well as composing
      Ecto queries.

    * Minimal library footprint: expose a small set of useful functions
      that application authors can use to set up their own optimal
      authorization API.

    * Minimal application footprint: "hide" Janus behind
      application-controlled policy modules that define the interface
      for the rest of the application.

    * Escape hatches: easily "drop down" to your own code when the
      declarative API doesn't cut it.

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
        |> allow(:read, Post)
        |> allow([:edit, :archive, :unarchive], Post, where: [user: [role: :member]])
        |> allow([:edit, :archive, :unarchive], Post, where: [user_id: mod.id])
        |> deny(:unarchive, Post, where: [archived_by: [role: :admin]])
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
