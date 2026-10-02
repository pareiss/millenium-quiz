defmodule MillenniumQuiz.Accounts.UserToken do
  use Ecto.Schema
  import Ecto.Query

  alias MillenniumQuiz.Accounts.UserToken

  @hash_algorithm :sha256
  @rand_size 32
  @session_validity_in_days 14

  schema "users_tokens" do
    field :token, :binary
    field :context, :string
    belongs_to :user, MillenniumQuiz.Accounts.User

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc """
  Generates a session token.

  The raw token goes into the (signed) session cookie, only its SHA-256
  hash is stored in the database. A leaked database dump therefore can't be
  used to hijack sessions. Deleting the row logs the session out.
  """
  def build_session_token(user) do
    token = :crypto.strong_rand_bytes(@rand_size)
    hashed_token = :crypto.hash(@hash_algorithm, token)
    {token, %UserToken{token: hashed_token, context: "session", user_id: user.id}}
  end

  @doc "Query returning the user (with token creation time) for a valid session token."
  def verify_session_token_query(token) do
    hashed_token = :crypto.hash(@hash_algorithm, token)

    from t in by_token_and_context_query(hashed_token, "session"),
      join: u in assoc(t, :user),
      where: t.inserted_at > ago(@session_validity_in_days, "day"),
      select: {u, t.inserted_at}
  end

  def by_token_and_context_query(hashed_token, context) do
    from UserToken, where: [token: ^hashed_token, context: ^context]
  end

  def delete_session_token_query(token) do
    by_token_and_context_query(:crypto.hash(@hash_algorithm, token), "session")
  end

  def by_user_and_contexts_query(user, contexts) do
    from t in UserToken, where: t.user_id == ^user.id and t.context in ^contexts
  end

  def session_validity_in_days, do: @session_validity_in_days
end
