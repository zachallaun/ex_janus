# Janus

<!-- MDOC -->

Flexible and composable authorization for resources backed by `Ecto` schemas.

If you need to answer either of these questions, this library may be of use to you:

- Is this user allowed to perform this action on this resource?
- What are all of the resources that this user can perform this action on?

Janus operates on a **policy**, which is a data structure created for a specific user that represents the actions they're allowed to perform.
You define policies by creating a **policy module** using the `Janus.Policy` API.

Janus tries to make very few assumptions about your code:

- it **does** assume you are using `Ecto` to define resources in your application
- it **does not** assume anything about the actors (users) in your system
  - you can use structs like `%User{}`,
  - or atoms like `:normal_user` and `:admin_user`
  - or `nil` to represent a logged-out user
- it **does not** assume anything about how you model user permissions
  - you can differentiate between separate structs like `%User{}` and `%Admin{}`
  - or use an `Ecto.Enum` like `role`
  - or store permissions dynamically in a separate table
- it **does not** assume anything about how you structure your code
  - you can define a single policy module that defines permissions for all of the resources in your application
  - or you can define separate policy modules for separate contexts
  - or you can compose policy modules from separate contexts into a single policy
- it **does not** assume that it is being used everywhere
  - you can use Janus where it makes sense and "hide" policy module usage inside contexts

## Usage

The API is intentionally minimal and is exposed by your policy module.

```elixir
# Authorize an action on a resource by some actor
{:ok, resource} = MyPolicy.authorize(resource, :some_action, some_user)

# Check whether the user has any access to resources in `ResourceSchema`
true = MyPolicy.any_authorized?(ResourceSchema, :some_action, some_user)

# Query resources that can have an action performed by some actor
%Ecto.Query{} = MyPolicy.authorized(ResourceSchema, :some_action, some_user)
```

For more, see the documentation for `authorize/4` and `authorized/4`.

## Policy Modules

See `Janus.Policy`.

## Example: Forum

Let's set up authorization rules for an example application: a forum.

For our purposes, our forum will have a very limited set of resources that we will consider:

- Threads
- Posts

We will also have 3 types of "actors" to be considered when defining authorization rules:

- Guests
- Users
- Moderators

We can imagine a number of authorization rules we'd like to be able to express:

- Guests can read public threads and posts, but cannot make posts themselves
- Users and Moderators can make new threads and posts
- Users can edit their own posts, but not others
- Users can archive their own posts, but not if it's the first post in a thread
- Moderators can edit or archive threads or posts

Here's what a basic policy module might look like:

```elixir
defmodule Discoarse.Policy do
  use Janus.Policy

  alias Discoarse.Accounts
  alias Discoarse.Forum

  @impl true
  def policy_for(policy \\ %Janus.Policy{}, actor)

  def policy_for(policy, %Accounts.User{roles: %{moderator: true}} = mod) do
    policy
    |> with_moderator_permissions(mod)
    |> with_user_permissions(mod)
    |> with_guest_permissions()
  end

  def policy_for(policy, %Accounts.User{} = user) do
    policy
    |> with_user_permissions(user)
    |> with_guest_permissions()
  end

  def policy_for(policy, nil) do
    policy
    |> with_guest_permissions()
  end

  defp with_guest_permissions(policy) do
    policy
    # Guests can read unarchived threads and unarchived posts in those threads
    |> allow(:read, Forum.Thread, where: [archived: false])
    |> allow(:read, Forum.Post, where: [archived: false, thread: allows(:read)])
  end

  defp with_user_permissions(policy, user) do
    policy
    # Users can see and edit their own profile
    |> allow([:read, :edit], Accounts.User, where: [id: user.id])
    # Users can create threads and edit their own thread
    |> allow(:create, Forum.Thread)
    |> allow(:edit, Forum.Thread, where: [creator: [id: user.id]])
    # Users can create posts and edit their own posts
    |> allow(:create, Forum.Post)
    |> allow(:edit, Forum.Post, where: [author: [id: user.id]])
    # Users can archive posts they can edit unless its the first post in a thread
    |> allow(:archive, Forum.Post, where: allows(:edit))
    |> forbid(:archive, Forum.Post, where: [index: 0])
  end

  defp with_moderator_permissions(policy, mod) do
    policy
    # Moderators can read, edit, and archive threads and posts
    |> allow([:read, :edit, :archive], Forum.Thread)
    # Note that moderators will not be able to archive the first post in a thread due to
    # the `forbid` rule in user permissions
    |> allow([:read, :edit, :archive], Forum.Post)
    # This could be overridden using `always_allow/3` instead:
    # |> always_allow(:archive, Forum.Post)
  end
end
```

This module defines the required callback `c:Janus.Policy.policy_for/2`, which expects a `%Janus.Policy{}` struct and the actor we're defining the policy for and returns a (potentially) modified policy struct.

In this example, we pattern-match on the actor to determine which permissions to apply to the policy.
We're able to compose permissions, as well: moderators additionally get user and guest permissions, and users additionally get guest permissions.
This kind of "stacking permissions" model doesn't always apply -- you may have completely tangential roles, or it may just be easier to maintain fully-independent policies.

The important bit is that you have the flexibility to modify the policy using whatever method works best for you.
Policy definitions are functional and data-centric -- they're "plain" Elixir.

This also means we can choose to organize our code however we want.
Right now, `Discoarse.Policy` is a single, central, cross-cutting concern that needs to know about and directly reference any resource we want to permission, e.g. knowing that you edit the `Discoarse.Accounts.User` to update the user's profile.
If better encapsulation is desired, policies could be defined per-context and composed at the top level:

```elixir
defmodule Discoarse.Policy do
  use Janus.Policy

  @impl true
  def policy_for(policy \\ %Janus.Policy{}, actor) do
    policy
    |> Discoarse.Forum.Policy.policy_for(actor)
    |> Discoarse.Accounts.Policy.policy_for(actor)
  end
end
```

Now that we've defined a policy, we can use it for two main purposes:

1. authorization checks (can the actor do _this_ to _thing_), and
2. data loading (fetch all the _things_ that the actor can do _this_ to).

Auth/permissions checks are done with `Janus.authorize/4`.
Data loading is done with `Janus.authorized/4`, which returns an `Ecto.Query`.
(Note that `use Janus.Policy` defined these functions on our policy module as well.)

```elixir
import Ecto.Query
alias Discoarse.{Forum, Repo}

# Imports `authorize/4` and `authorized/4`.
use Discoarse.Policy

# Authorize individual resources
{:ok, thread} = authorize(thread, :edit, moderator)
{:ok, thread} = authorize(thread, :edit, user)
:error = authorize(thread, :edit, nil)

# Filter a query to those that are authorized
Forum.Thread
|> order_by(desc: :inserted_at)
|> authorized(:edit, user)
|> Repo.all()

authorized(Forum.Thread, :edit, user)
```


<!-- MDOC -->

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed by adding `janus` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:janus, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc) and published on [HexDocs](https://hexdocs.pm).
Once published, the docs can be found at <https://hexdocs.pm/janus>.

## Development

Steps to set up `Janus` locally:

```bash
$ git clone https://github.com/zachallaun/janus && cd janus
$ mix deps.get
$ mix ecto.setup
$ mix test
```
