# Janus

Authorization superpowers for your `Ecto` schemas.

Janus prioritizes:

* Single source of truth: authorization rules should be defined once and used for authorizing individual actions as well as composing Ecto queries.
* Minimal library footprint: favor a small set of powerful that applications can use to expose their own optimal authorization API.
* Minimal application footprint: where possible, "hide" Janus behind user-controlled policy modules that implement well-defined behaviours.
* Escape hatches: easily "drop down" to your own code when the declarative API doesn't cut it.

[**Documentation**](https://hexdocs.pm/ex_janus/Janus.html)

## Installation

Janus can be installed by adding `ex_janus` to your deps in `mix.exs`:

```elixir
defp deps do
  [
    {:ex_janus, "~> 0.1.0"}
  ]
end
```

## Development

To set up and test `Janus` locally:

```bash
$ git clone https://github.com/zachallaun/ex_janus && cd ex_janus

$ mix deps.get

# Set up test database and run tests with code coverage report
$ mix setup
$ mix t
```
