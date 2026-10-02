defmodule MillenniumQuiz.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  schema "users" do
    field :username, :string
    field :password, :string, virtual: true, redact: true
    field :hashed_password, :string, redact: true

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating an admin user.

  ## Options

    * `:hash_password` - Hashes the password so it can be stored securely.
      Defaults to `true`. Disable it for live form validations.
  """
  def registration_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:username, :password])
    |> validate_username()
    |> validate_password(opts)
  end

  @doc "Changeset for changing the password."
  def password_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:password])
    |> validate_confirmation(:password, message: "does not match password")
    |> validate_password(opts)
  end

  defp validate_username(changeset) do
    changeset
    |> update_change(:username, &(&1 |> String.trim() |> String.downcase()))
    |> validate_required([:username])
    |> validate_length(:username, min: 3, max: 30)
    |> validate_format(:username, ~r/^[a-z0-9_]+$/,
      message: "only lowercase letters, digits and underscores"
    )
    |> unsafe_validate_unique(:username, MillenniumQuiz.Repo)
    |> unique_constraint(:username)
  end

  defp validate_password(changeset, opts) do
    changeset
    |> validate_required([:password])
    |> validate_length(:password, min: 12, max: 72)
    |> maybe_hash_password(opts)
  end

  defp maybe_hash_password(changeset, opts) do
    password = get_change(changeset, :password)

    if Keyword.get(opts, :hash_password, true) && password && changeset.valid? do
      changeset
      # Bcrypt generates a random salt per hash and embeds it in the result.
      |> put_change(:hashed_password, Bcrypt.hash_pwd_salt(password))
      |> delete_change(:password)
    else
      changeset
    end
  end

  @doc """
  Verifies the password.

  If there is no user or the user doesn't have a password, we call
  `Bcrypt.no_user_verify/0` to avoid timing attacks.
  """
  def valid_password?(%__MODULE__{hashed_password: hashed_password}, password)
      when is_binary(hashed_password) and byte_size(password) > 0 do
    Bcrypt.verify_pass(password, hashed_password)
  end

  def valid_password?(_, _) do
    Bcrypt.no_user_verify()
    false
  end
end
