defmodule MillenniumQuiz.Accounts.Scope do
  @moduledoc """
  Defines the scope of the caller to be used throughout the app.

  Right now it only carries the logged-in admin. Later it can grow fields
  such as roles or a tenant/organisation without touching every call site.
  """

  alias MillenniumQuiz.Accounts.User

  defstruct user: nil

  def for_user(%User{} = user), do: %__MODULE__{user: user}
  def for_user(nil), do: nil
end
