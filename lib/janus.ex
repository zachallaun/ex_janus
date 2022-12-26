defmodule Janus do
  @moduledoc """
  Authorization superpowers for your `Ecto` schemas.

  Janus prioritizes:

    * Single source of truth: authorization rules should be defined once and used for
      authorizing individual actions as well as composing Ecto queries.
    * Minimal library footprint: favor a small set of powerful that applications can use
      to expose their own optimal authorization API.
    * Minimal application footprint: where possible, "hide" Janus behind user-controlled
      policy modules that implement well-defined behaviours.
    * Escape hatches: easily "drop down" to your own code when the declarative API doesn't
      cut it.

  Janus is split into two primary components:

    * `Janus.Policy` - functions and behaviour for defining _policy modules_, which
      describe the allowed actors, actions, and resources in your application. This is
      where you look if you're writing a policy module.
    * `Janus.Authorization` - functions and behaviour used by the rest of your
      application to authorize and load resources. This is where you look if you're using
      a policy module.

  Janus defines a Mix task to generate the basic policy module that will get you started:

      $ mix janus.gen.policy

  ## Policies

  Policy modules are created by invoking `use Janus`, which implements both the
  `Janus.Policy` and `Janus.Authorization` behaviours:

      defmodule Policy do
        use Janus

        @impl true
        def policy_for(policy, _user) do
          policy
        end
      end

  When you invoke `use Janus`, default implementations are injected for required
  callbacks, except for `c:Janus.Policy.policy_for/2`. This callback is your foundation,
  as it returns the authorization policy for an individual user of your application.

  The policy above is not very useful -- it doesn't allow anyone to do anything -- but
  that can be changed by using the `Janus.Policy` API to define actions, resources, and
  conditions that make up your authorization rules.

      def policy_for(policy, %User{role: :moderator} = mod) do
        policy
        |> allow(:read, Post)
        |> allow([:edit, :archive, :unarchive], Post, where: [user: [role: :member]])
        |> allow([:edit, :archive, :unarchive], Post, where: [user_id: mod.id])
        |> deny(:unarchive, Post, where: [archived_by: [role: :admin]])
      end

  See the `Janus.Policy` documentation for more on defining policies.

  ## Authorization

  With our policy module defined, it can now be used to load and authorize resources.

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

  These functions make up the `Janus.Authorization` behaviour, and their definitions
  were injected by default when we invoked `use Janus`. This is the "public API" that the
  rest of your application will use to authorize resources.

  See the `Janus.Authorization` documentation for more.

  ## Integration with `Ecto.Query`

  The primary assumption that Janus makes is that your resources are backed by an
  `Ecto.Schema`. Using Ecto's schema reflection capabilities, Janus is able to use the
  same policy to authorize a single resource and to construct a composable Ecto query
  that is aware of field types and associations.

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

  ## Integration with `Ecto.Changeset`

  Janus provides an additional utility, `Janus.Authorization.validate_authorized/4`, that
  can be used to expose authorization failures as a validation error on a changeset.

  This is especially useful when updating a resource, where you may want to check both
  that the resource is authorized prior to the update and that it is _still_ authorized
  after applying the changes. Here's how this would look using Janus:

      def update_post(post, attrs, current_user) do
        post
        |> Post.changeset(attrs)
        |> Policy.validate_authorized(:update, current_user)
        |> Repo.update()
      end

  In the example above, if the post is unauthorized either before or after applying the
  changes, the operation would fail.
  """

  require Ecto.Query

  @type action :: any()
  @type schema_module :: module()
  @type actor :: any()

  @doc """
  Sets up a module to implement the `Janus.Policy` and `Janus.Authorization` behaviours.

  Invoking `use Janus` does the following:

    * invokes `use Janus.Policy` which imports functions for defining policies and
      injects wrapper definitions for `policy_for/1` and `policy_for/2` that support
      hooks (see `Janus.Policy` for more)
    * injects implementations for the `Janus.Authorization` behaviour

  ## Example

      defmodule MyApp.Policy do
        use Janus

        @impl true
        def policy_for(policy, _actor) do
          policy
        end
      end

      # imports `authorize`, `scope`, and `any_authorized?`
      use MyApp.Policy
  """
  defmacro __using__(_opts) do
    quote location: :keep do
      @behaviour Janus.Authorization

      use Janus.Policy
      require Janus

      @impl Janus.Authorization
      def authorize(resource, action, actor, opts \\ []) do
        Janus.Authorization.authorize(resource, action, policy_for(actor), opts)
      end

      @impl Janus.Authorization
      def any_authorized?(schema, action, actor) do
        Janus.Authorization.any_authorized?(schema, action, policy_for(actor))
      end

      @impl Janus.Authorization
      def scope(query_or_schema, action, actor, opts \\ []) do
        Janus.Authorization.scope(query_or_schema, action, policy_for(actor), opts)
      end

      @impl Janus.Authorization
      def validate_authorized(changeset, action, actor, opts \\ []) do
        Janus.Authorization.validate_authorized(changeset, action, policy_for(actor), opts)
      end
    end
  end
end
