defmodule MillenniumQuiz.Accounts do
  @moduledoc """
  Admin accounts: username/password login with bcrypt and DB-backed sessions.
  """

  import Ecto.Query, warn: false

  alias MillenniumQuiz.Repo
  alias MillenniumQuiz.Accounts.{User, UserToken}

  ## Users

  def list_users do
    Repo.all(from u in User, order_by: u.username)
  end

  def get_user!(id), do: Repo.get!(User, id)

  @doc "The user with this id, or nil (also for ids that aren't valid)."
  def get_user(id) do
    case Ecto.Type.cast(:id, id) do
      {:ok, id} -> Repo.get(User, id)
      :error -> nil
    end
  end

  def get_user_by_username(username) when is_binary(username) do
    Repo.get_by(User, username: username)
  end

  def get_user_by_username_and_password(username, password)
      when is_binary(username) and is_binary(password) do
    user = Repo.get_by(User, username: String.downcase(String.trim(username)))
    if User.valid_password?(user, password), do: user
  end

  def register_user(attrs) do
    %User{}
    |> User.registration_changeset(attrs)
    |> Repo.insert()
  end

  def change_user_registration(%User{} = user, attrs \\ %{}, opts \\ []) do
    User.registration_changeset(user, attrs, opts)
  end

  def change_user_password(%User{} = user, attrs \\ %{}, opts \\ []) do
    User.password_changeset(user, attrs, opts)
  end

  @doc """
  Updates the password after checking the current one.

  All session tokens of the user are deleted, so other devices are logged out.
  """
  def update_user_password(%User{} = user, current_password, attrs) do
    changeset =
      user
      |> User.password_changeset(attrs)
      |> then(fn changeset ->
        if User.valid_password?(user, current_password) do
          changeset
        else
          Ecto.Changeset.add_error(changeset, :current_password, "is not valid")
        end
      end)

    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, changeset)
    |> Ecto.Multi.delete_all(
      :deleted,
      UserToken.by_user_and_contexts_query(user, ["session"])
    )
    |> Repo.transaction()
    |> case do
      {:ok, %{user: user}} -> {:ok, user}
      {:error, :user, changeset, _} -> {:error, changeset}
    end
  end

  def delete_user(%User{} = user), do: Repo.delete(user)

  ## Session

  def generate_user_session_token(user) do
    {token, user_token} = UserToken.build_session_token(user)
    Repo.insert!(user_token)
    token
  end

  @doc "Returns `{user, token_inserted_at}` or nil."
  def get_user_by_session_token(token) do
    token
    |> UserToken.verify_session_token_query()
    |> Repo.one()
  end

  def delete_user_session_token(token) do
    Repo.delete_all(UserToken.delete_session_token_query(token))
    :ok
  end
end
