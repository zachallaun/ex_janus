# Adapted from Phoenix Framework:
# https://github.com/phoenixframework/phoenix/blob/aead257f9303e2d7578be9e5250508a801974ad1/installer/test/mix_helper.exs
#
# The license for that project has been copied here:
#
# MIT License
#
# Copyright (c) 2014 Chris McCord
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

defmodule MixHelper do
  import ExUnit.Assertions

  def tmp_path do
    Path.expand("../tmp", __DIR__)
  end

  def in_tmp_project(name, function) do
    random_root = Path.join([tmp_path(), random_string(10)])

    try do
      in_project(random_root, name, function)
    after
      File.rm_rf!(random_root)
    end
  end

  def in_project(name, function) do
    random_root = Path.join([tmp_path(), random_string(10)])
    in_project(random_root, name, function)
  end

  def in_project(root, name, function) do
    path = Path.join([root, to_string(name)])

    File.rm_rf!(path)
    File.mkdir_p!(path)

    File.cd!(path, fn ->
      File.touch!("mix.exs")

      File.write!(".formatter.exs", """
      [
        import_deps: [:ecto, :ecto_sql, :ex_janus],
        inputs: ["*.exs"]
      ]
      """)

      function.()
    end)

    root
  end

  defp random_string(len) do
    len |> :crypto.strong_rand_bytes() |> Base.encode64() |> binary_part(0, len)
  end

  def assert_file(file) do
    assert File.regular?(file), "Expected #{file} to exist, but does not"
  end

  def refute_file(file) do
    refute File.regular?(file), "Expected #{file} to not exist, but it does"
  end

  def assert_file(file, match) do
    cond do
      is_list(match) ->
        assert_file(file, &Enum.each(match, fn m -> assert &1 =~ m end))

      is_binary(match) or is_struct(match, Regex) ->
        assert_file(file, &assert(&1 =~ match))

      is_function(match, 1) ->
        assert_file(file)
        match.(File.read!(file))

      true ->
        raise inspect({file, match})
    end
  end
end
