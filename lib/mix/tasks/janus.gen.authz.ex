defmodule Mix.Tasks.Janus.Gen.Authz do
  @moduledoc """
  Creates an Authorization and Policy module.

      $ mix janus.gen.authz

  Creates the following files:

    * `lib/app_name/authz.ex` - Authorization API used by the rest
      of your application to load and authorize resources.
    * `lib/app_name/authz/policy.ex` - Policy definition containing
      authorization rules.

  ## Options

    * `--authz` - The name of the generated Authorization module.
      Defaults to `Authz`.
    * `--policy` - The name of the generated Policy module. Defaults to
      `Policy`.
    * `--app` - The name of the app (camelized, e.g. `MyApp`). Defaults
      to the camelized variant of your OTP app name.
  """

  use Mix.Task

  @doc false
  def run(args) do
    parsed = parse_args(args)

    opts = [
      app: parsed[:app],
      authz_module: authz_module(parsed),
      policy_module: policy_module(parsed)
    ]

    copy_from("priv/templates", opts, [
      {"authz.ex.eex", dest(opts[:authz_module])},
      {"policy.ex.eex", dest(opts[:policy_module])}
    ])
  end

  defp copy_from(source_dir, binding, mapping) do
    for {source_file, target} <- mapping do
      source = :ex_janus |> Application.app_dir(source_dir) |> Path.join(source_file)
      Mix.Generator.create_file(target, EEx.eval_file(source, binding))
    end
  end

  defp parse_args(args) do
    options = [authz: :string, policy: :string, app: :string]
    {opts, []} = OptionParser.parse!(args, strict: options)

    opts
    |> Keyword.put_new_lazy(:app, &app_namespace/0)
    |> Keyword.put_new(:authz, "Authz")
    |> Keyword.put_new(:policy, "Policy")
  end

  defp dest(module_name) do
    "lib/" <> Macro.underscore(module_name) <> ".ex"
  end

  defp authz_module(args) do
    "#{args[:app]}.#{args[:authz]}"
    |> parse_module!()
    |> display_name()
  end

  defp policy_module(args) do
    "#{args[:app]}.#{args[:authz]}.#{args[:policy]}"
    |> parse_module!()
    |> display_name()
  end

  defp display_name(module) do
    "Elixir." <> name = to_string(module)
    name
  end

  defp parse_module!(module) when is_binary(module) do
    module
    |> String.split(".")
    |> Module.concat()
    |> parse_module!()
  end

  defp parse_module!(module) when is_atom(module) do
    module
    |> ensure_alias!()
    |> ensure_unused!()
  end

  defp ensure_unused!(module) do
    if Code.ensure_loaded?(module) do
      Mix.raise(
        "Module name `#{inspect(module)}` is already taken. Please specify another using --module."
      )
    end

    module
  end

  defp ensure_alias!(module) do
    unless Macro.classify_atom(module) == :alias do
      Mix.raise(
        "Module name `#{display_name(module)}` is invalid. Expected an alias, e.g. `Policy`"
      )
    end

    module
  end

  defp app_namespace do
    otp_app() |> to_string() |> Macro.camelize()
  end

  defp otp_app do
    Mix.Project.config() |> Keyword.fetch!(:app)
  end
end
