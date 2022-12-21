defmodule Mix.Tasks.Janus.Gen.Policy do
  @shortdoc "Generates a basic policy module"
  @moduledoc """
  Creates a basic policy module.

      $ mix janus.gen.policy [--module MODULE] [--path PATH]

  Creates the following file:

    * `lib/app_name/policy.ex` - A Janus policy module containing additional authorization
      helpers

  ## Options

    * `--module` - The name of the generated module, defaults to `AppName.Policy`

    * `--path` - The path (including filename) for the generated module, defaults to
      `lib/app_name/policy.ex`
  """

  use Mix.Task

  @doc false
  def run(args) do
    opts = parse_args(args)

    copy_from("priv/templates", opts, [
      {"policy.ex.eex", opts[:path]}
    ])
  end

  defp copy_from(source_dir, binding, mapping) do
    for {source_file, target} <- mapping do
      source = :janus |> Application.app_dir(source_dir) |> Path.join(source_file)
      Mix.Generator.create_file(target, EEx.eval_file(source, binding))
    end
  end

  defp parse_args(args) do
    {opts, []} = OptionParser.parse!(args, strict: [module: :string, path: :string])

    opts
    |> Keyword.put_new_lazy(:module, &default_module/0)
    |> Keyword.update!(:module, &parse_module!/1)
    |> Keyword.update!(:module, &module_to_string!/1)
    |> Keyword.put_new_lazy(:path, &default_path/0)
    |> Keyword.put_new_lazy(:app_namespace, &app_namespace/0)
  end

  defp default_path do
    "lib/#{otp_app()}/policy.ex"
  end

  defp default_module do
    Module.concat(app_namespace(), Policy)
  end

  defp module_to_string!(module) when is_atom(module) do
    case to_string(module) do
      "Elixir." <> module -> module
      module -> module
    end
  end

  defp parse_module!(module) when is_atom(module) do
    ensure_unused!(module)
  end

  defp parse_module!(module) when is_binary(module) do
    module
    |> String.split(".")
    |> Module.concat()
    |> ensure_unused!()
  end

  defp ensure_unused!(module) do
    name = Module.concat(Elixir, module)

    if Code.ensure_loaded?(name) do
      Mix.raise(
        "Module name #{inspect(module)} is already taken. Please specify another using --module."
      )
    else
      module
    end
  end

  defp app_namespace do
    otp_app() |> to_string() |> Macro.camelize()
  end

  defp otp_app do
    Mix.Project.config() |> Keyword.fetch!(:app)
  end
end
