<!-- MDOC -->

Flexible and composable authorization for resources defined by `Ecto` schemas.

## Example: Forum

Let's set up authorization rules for an example application: a forum.

For our purposes, our forum will have a very limited set of resources that we will consider:

- Threads
- Posts
- Profiles

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
  use Janus

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
  use Janus

  @impl true
  def policy_for(policy \\ %Janus.Policy{}, actor) do
    policy
    |> Discoarse.Forum.Policy.policy_for(actor)
    |> Discoarse.Accounts.Policy.policy_for(actor)
  end
end
```

### Usage

Now that we've defined a policy, we can use it for two main functions:

1. authorization checks (can the actor do _this_ to _thing_), and
2. data loading (fetch all the _things_ that the actor can do _this_ to).

Auth/permissions checks are done with `c:Janus.Policy.allows?/3` and `c:Janus.Policy.forbids?/3`.
Data loading is done with `c:Janus.Policy.accessible/3`, which returns a composable `Ecto.Query`.

```elixir
import Ecto.Query

alias Discoarse.{Accounts, Forum, Policy, Repo}

# Authorization checks
Policy.allows?(moderator, :edit, some_thread) #=> true, mods can edit all threads
Policy.allows?(user, :edit, some_thread) #=> true if the user created the thread
Policy.allows?(nil, :edit, some_thread) #=> false, guests can't edit any threads

# Data loading
Forum.Thread
|> Policy.accessible(:edit, user)
|> order_by(desc: :inserted_at)
|> Repo.all()
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

