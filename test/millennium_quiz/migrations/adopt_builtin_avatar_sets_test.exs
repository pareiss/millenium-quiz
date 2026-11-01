defmodule MillenniumQuiz.Repo.Migrations.AdoptBuiltinAvatarSetsTest do
  # Rolls migrations back and forward inside the test transaction: not async.
  use MillenniumQuiz.DataCase, async: false

  import Ecto.Query, only: [from: 2]

  alias MillenniumQuiz.Avatars
  alias MillenniumQuiz.Quiz.{CardAvatarCrop, Format, FormatAvatarCard}

  @version 20_261_101_135_710

  defp migrations, do: Application.app_dir(:millennium_quiz, "priv/repo/migrations")

  setup do
    Code.put_compiler_option(:ignore_module_conflict, true)
    on_exit(fn -> Code.put_compiler_option(:ignore_module_conflict, false) end)
    Repo.delete_all(Format)
    :ok
  end

  defp migrate_up do
    Ecto.Migrator.run(Repo, migrations(), :down, to: @version, log: false, migration_lock: false)
    Ecto.Migrator.run(Repo, migrations(), :up, to: @version, log: false, migration_lock: false)
  end

  defp format!(name, date) do
    %{rows: [[id]]} =
      Repo.query!(
        "INSERT INTO formats (name, date, inserted_at, updated_at) VALUES ($1, $2, now(), now()) RETURNING id",
        [name, date]
      )

    id
  end

  defp card!(password, release \\ ~D[2002-03-08]) do
    %{rows: [[id]]} =
      Repo.query!(
        """
        INSERT INTO cards (password, name, tcg_release_date, names, texts, fetched_at, inserted_at, updated_at)
        VALUES ($1, $2, $3, '{}', '{}', now(), now(), now())
        ON CONFLICT (password) DO UPDATE SET name = excluded.name RETURNING id
        """,
        [password, "Card #{password}", release]
      )

    id
  end

  defp links(format_id) do
    Repo.all(
      from fa in FormatAvatarCard,
        join: c in MillenniumQuiz.Cards.Card,
        on: c.id == fa.card_id,
        where: fa.format_id == ^format_id,
        order_by: fa.position,
        select: c.password
    )
  end

  defp set_passwords(date), do: Enum.map(Avatars.set_for(date), & &1.password)

  test "does nothing on an empty pool or without formats" do
    migrate_up()
    assert Repo.aggregate(FormatAvatarCard, :count) == 0

    id = format!("Edison", ~D[2010-04-24])
    migrate_up()
    assert links(id) == []
    assert Repo.aggregate(CardAvatarCrop, :count) == 0
  end

  test "links a complete set in order, with crops, and does it only once" do
    edison = format!("Edison", ~D[2010-04-24])
    other = format!("Other", ~D[2020-01-01])
    for pw <- set_passwords(~D[2010-04-24]), do: card!(pw)

    migrate_up()
    assert links(edison) == set_passwords(~D[2010-04-24])
    assert links(other) == []

    for m <- Avatars.set_for(~D[2010-04-24]) do
      c = Avatars.face_crop(m.face)

      assert %{rows: [[x, y, zoom]]} =
               Repo.query!(
                 "SELECT x, y, zoom FROM card_avatar_crops cr JOIN cards c ON c.id = cr.card_id WHERE c.password = $1",
                 [m.password]
               )

      assert %{x: x, y: y, zoom: zoom} == c
    end

    rows = Repo.aggregate(FormatAvatarCard, :count)
    migrate_up()
    assert Repo.aggregate(FormatAvatarCard, :count) == rows
  end

  test "leaves an incomplete set, a late card and a format with its own cards alone" do
    incomplete = format!("Edison", ~D[2010-04-24])
    [_missing | present] = set_passwords(~D[2010-04-24])
    for pw <- present, do: card!(pw)

    late = format!("Goat", ~D[2005-04-01])
    [late_pw | rest] = set_passwords(~D[2005-04-01])
    card!(late_pw, ~D[2020-01-01])
    for pw <- rest, do: card!(pw)

    own = format!("Tengu", ~D[2011-09-01])
    [first | others] = set_passwords(~D[2011-09-01])
    first_id = card!(first)
    for pw <- others, do: card!(pw)

    Repo.query!(
      "INSERT INTO format_avatar_cards (format_id, card_id, position) VALUES ($1, $2, 0)",
      [own, first_id]
    )

    migrate_up()
    assert links(incomplete) == []
    assert links(late) == []
    assert links(own) == [first]
  end

  test "keeps a crop that is stored already" do
    edison = format!("Edison", ~D[2010-04-24])
    [first | rest] = set_passwords(~D[2010-04-24])
    id = card!(first)
    for pw <- rest, do: card!(pw)

    Repo.query!("INSERT INTO card_avatar_crops (card_id, x, y, zoom) VALUES ($1, 5, 95, 110)", [
      id
    ])

    migrate_up()
    assert length(links(edison)) == length(rest) + 1

    assert %{rows: [[5, 95, 110]]} =
             Repo.query!("SELECT x, y, zoom FROM card_avatar_crops WHERE card_id = $1", [id])
  end

  test "rolling back is allowed and keeps the rows" do
    edison = format!("Edison", ~D[2010-04-24])
    for pw <- set_passwords(~D[2010-04-24]), do: card!(pw)
    migrate_up()
    Ecto.Migrator.run(Repo, migrations(), :down, to: @version, log: false, migration_lock: false)
    assert length(links(edison)) == length(set_passwords(~D[2010-04-24]))
  end
end
