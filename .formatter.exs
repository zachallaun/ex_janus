locals_without_parens = [
  before_policy_for: 1
]

[
  import_deps: [:ecto, :ecto_sql],
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"],
  locals_without_parens: locals_without_parens,
  export: [locals_without_parens: locals_without_parens]
]
