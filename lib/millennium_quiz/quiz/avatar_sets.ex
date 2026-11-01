defmodule MillenniumQuiz.Quiz.AvatarSets do
  @moduledoc """
  Moves the built-in profile-picture sets of `MillenniumQuiz.Avatars` (Edison,
  Goat, Tengu) into the table, so that admins own them: the cards become the
  format's `format_avatar_cards`, with a crop per card
  (`Avatars.face_crop/1`) unless one is stored already.

  A migration (`AdoptBuiltinAvatarSets`) does this for the cards that are in
  the pool already. `adopt/1` does the rest: it fetches the missing cards from
  the remote sources, one at a time with a pause, as a backup restore does.

  Rules, so that it is safe to run again and again:

    * only a format whose date has a set and that has **no** profile-picture
      cards is touched; an admin's list is never changed;
    * a set is adopted whole or not at all: a card that cannot be fetched (or
      came out after the format's date) leaves the format as it is, using the
      built-in set in code, and is reported. Cards that were fetched stay in the
      pool and are not fetched again next time;
    * a crop that is stored for a card is kept.

  Games saved before keep their pictures: a game stores the slug of each
  picture (`"jinzo"`, `"card-12"`), and `Avatars.path/2` still serves the
  committed image of every built-in slug.

  Options: `:fetch` (default true; false uses the pool only, no network) and
  `:pause_ms` (between remote fetches, default as `Cards.refresh_all/0`).

  Returns one `%{format: name, status: status, missing: [names]}` per format
  with a set, `status` being `:adopted`, `:already` (it has cards of its own)
  or `:incomplete` (`missing` says which cards could not be had).
  """
  import Ecto.Query, only: [from: 2]

  alias MillenniumQuiz.{Avatars, Cards, Quiz, Repo}
  alias MillenniumQuiz.Cards.Card
  alias MillenniumQuiz.Quiz.{CardAvatarCrop, Format, FormatAvatarCard}

  @type result :: %{
          format: String.t(),
          status: :adopted | :already | :incomplete,
          missing: [String.t()]
        }

  @spec adopt(keyword) :: [result]
  def adopt(opts \\ []) do
    fetch? = Keyword.get(opts, :fetch, true)

    pause =
      Keyword.get_lazy(opts, :pause_ms, fn ->
        Application.get_env(:millennium_quiz, Cards, [])[:refresh_pause_ms] || 250
      end)

    formats =
      Repo.all(
        from f in Format,
          where: f.date in ^Avatars.set_dates(),
          order_by: [asc: f.date, asc: f.id],
          select: struct(f, [:id, :name, :date])
      )

    {results, _state} =
      Enum.map_reduce(formats, %{fetches: 0}, fn format, state ->
        if has_cards?(format) do
          {%{format: format.name, status: :already, missing: []}, state}
        else
          adopt_format(format, fetch?, pause, state)
        end
      end)

    results
  end

  defp has_cards?(format),
    do: Repo.exists?(from fa in FormatAvatarCard, where: fa.format_id == ^format.id)

  defp adopt_format(format, fetch?, pause, state) do
    monsters = Avatars.set_for(format.date)

    {found, state} =
      Enum.map_reduce(monsters, state, fn monster, state ->
        {card, state} = resolve(monster.password, fetch?, pause, state)
        {{monster, card}, state}
      end)

    case for({monster, nil} <- found, do: monster.name) do
      [] -> {link(format, found), state}
      missing -> {%{format: format.name, status: :incomplete, missing: missing}, state}
    end
  end

  # The pool first; the sources only for what it lacks, one at a time.
  defp resolve(password, fetch?, pause, state) do
    cond do
      card =
          Repo.one(
            from c in Card,
              where: c.password == ^password,
              select: struct(c, [:id, :tcg_release_date])
          ) ->
        {card, state}

      fetch? ->
        if state.fetches > 0, do: Process.sleep(pause)
        {fetch(password), %{state | fetches: state.fetches + 1}}

      true ->
        {nil, state}
    end
  end

  defp fetch(password) do
    case Cards.import(password) do
      {:ok, card} -> %Card{id: card.id}
      {:error, _} -> nil
    end
  rescue
    _ -> nil
  end

  defp link(format, found) do
    result =
      Repo.transaction(fn ->
        for {monster, card} <- found do
          case Quiz.add_avatar_card(format.id, card.id) do
            {:ok, _} -> :ok
            {:error, _} -> Repo.rollback(monster.name)
          end
        end

        for {monster, card} <- found,
            not Repo.exists?(from c in CardAvatarCrop, where: c.card_id == ^card.id) do
          {:ok, _} = Quiz.set_avatar_crop(card.id, Avatars.face_crop(monster.face))
        end
      end)

    case result do
      {:ok, _} -> %{format: format.name, status: :adopted, missing: []}
      {:error, name} -> %{format: format.name, status: :incomplete, missing: [name]}
    end
  end
end
