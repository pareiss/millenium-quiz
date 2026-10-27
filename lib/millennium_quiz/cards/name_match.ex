defmodule MillenniumQuiz.Cards.NameMatch do
  @moduledoc """
  Matching a typed query against card names, for the pool (`Cards.suggest/2`)
  and the list of all names (`CardNames.search/3`): case-insensitive
  "contains", with `%`, `_` and `\\` in the query taken literally, ranked exact
  match, name starts with the query, a word starts with the query, anything
  else; then alphabetically. Works on any query whose first binding has a
  `name`.
  """
  import Ecto.Query

  def matching(queryable, query) when is_binary(query) do
    like = escape_like(query)
    lower = String.downcase(query)

    from c in queryable,
      where: fragment("lower(?) LIKE lower(?)", c.name, ^"%#{like}%"),
      order_by: [
        asc:
          fragment(
            """
            CASE WHEN lower(?) = lower(?) THEN 0
                 WHEN lower(?) LIKE lower(?) THEN 1
                 WHEN lower(?) LIKE lower(?) THEN 2
                 ELSE 3 END
            """,
            c.name,
            ^lower,
            c.name,
            ^"#{like}%",
            c.name,
            ^"% #{like}%"
          ),
        asc: fragment("lower(?)", c.name),
        asc: c.id
      ]
  end

  defp escape_like(string), do: String.replace(string, ["\\", "%", "_"], &"\\#{&1}")
end
