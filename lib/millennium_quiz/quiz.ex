defmodule MillenniumQuiz.Quiz do
  @moduledoc """
  Admin-managed quiz content: formats, their 2-6 topics and the
  difficulty-ordered questions of each topic.
  """

  import Ecto.Query, warn: false

  alias MillenniumQuiz.Repo
  alias MillenniumQuiz.Cards.Card
  alias MillenniumQuiz.Avatars

  alias MillenniumQuiz.Quiz.{
    CardAvatarCrop,
    Format,
    FormatAvatarCard,
    Topic,
    Question,
    Submission
  }

  ## Formats

  def list_formats do
    Repo.all(from f in Format, order_by: f.name, preload: [topics: :questions])
  end

  @doc "Formats that can be played: at least 2 topics and 1 question."
  def list_playable_formats do
    question_counts =
      from t in Topic,
        left_join: q in assoc(t, :questions),
        group_by: t.format_id,
        select: %{
          format_id: t.format_id,
          topics: count(t.id, :distinct),
          questions: count(q.id)
        }

    Repo.all(
      from f in Format,
        join: s in subquery(question_counts),
        on: s.format_id == f.id,
        where: s.topics >= ^Format.min_topics() and s.questions > 0,
        order_by: f.name,
        select: %{format: f, topics: s.topics, questions: s.questions}
    )
  end

  @doc """
  The format with its topics, their questions and its avatar card links
  (`avatar_cards`: ids and positions only, no artwork), so a game can pick
  its pictures with `Avatars.pool/1`.
  """
  def get_format!(id) do
    Format
    |> Repo.get!(id)
    |> Repo.preload([:avatar_cards, topics: :questions])
  end

  def create_format(attrs) do
    %Format{topics: []}
    |> Format.changeset(attrs)
    |> Repo.insert()
  end

  def update_format(%Format{} = format, attrs) do
    format
    |> Format.changeset(attrs)
    |> Repo.update()
  end

  def delete_format(%Format{} = format), do: Repo.delete(format)

  def change_format(%Format{} = format, attrs \\ %{}) do
    Format.changeset(format, attrs)
  end

  ## Avatar cards

  @max_avatar_cards 40

  @doc "The most cards a format can have as profile pictures."
  def max_avatar_cards, do: @max_avatar_cards

  @doc """
  The cards chosen as the profile pictures of the format, in order, as
  `%Card{id, name, password}` (only those columns: never the artwork).
  """
  def avatar_cards(format_id) do
    Repo.all(
      from fa in FormatAvatarCard,
        join: c in Card,
        on: c.id == fa.card_id,
        where: fa.format_id == ^format_id,
        order_by: [asc: fa.position, asc: fa.id],
        select: struct(c, [:id, :name, :password])
    )
  end

  @doc """
  Adds the card at the end of the format's list. Adding a card that is
  already there changes nothing.

  Returns `{:ok, %FormatAvatarCard{}}`, `{:error, :limit}` (see
  `max_avatar_cards/0`), `{:error, :not_released}` (the card came out after
  the format's date; a card without a release date counts as released, as in
  `Cards.suggest/2`) or `{:error, :not_found}` (no such format or card).
  """
  def add_avatar_card(format_id, card_id) do
    Repo.transaction(fn ->
      # the lock keeps two admins from passing the limit together
      with %Format{} = format <-
             Repo.one(from f in Format, where: f.id == ^format_id, lock: "FOR UPDATE"),
           %Card{} = card <-
             Repo.one(
               from c in Card,
                 where: c.id == ^card_id,
                 select: struct(c, [:id, :tcg_release_date])
             ),
           :ok <- check_released(card, format) do
        insert_avatar_card(format.id, card.id)
      else
        nil -> Repo.rollback(:not_found)
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp check_released(%{tcg_release_date: nil}, _format), do: :ok
  defp check_released(_card, %{date: nil}), do: :ok

  defp check_released(card, format) do
    if Date.compare(card.tcg_release_date, format.date) == :gt,
      do: {:error, :not_released},
      else: :ok
  end

  defp insert_avatar_card(format_id, card_id) do
    case Repo.get_by(FormatAvatarCard, format_id: format_id, card_id: card_id) do
      %FormatAvatarCard{} = existing ->
        existing

      nil ->
        {count, max} =
          Repo.one(
            from fa in FormatAvatarCard,
              where: fa.format_id == ^format_id,
              select: {count(fa.id), max(fa.position)}
          )

        if count >= @max_avatar_cards do
          Repo.rollback(:limit)
        else
          Repo.insert!(%FormatAvatarCard{
            format_id: format_id,
            card_id: card_id,
            position: (max || -1) + 1
          })
        end
    end
  end

  @doc "Removes the card from the format's list. Always `:ok`, also when it wasn't there."
  def remove_avatar_card(format_id, card_id) do
    Repo.delete_all(
      from fa in FormatAvatarCard, where: fa.format_id == ^format_id and fa.card_id == ^card_id
    )

    :ok
  end

  ## Avatar crops

  @doc """
  The cards of `avatar_cards/1` with their crops:
  `[%{card: %Card{id, name, password}, crop: %{x, y, zoom}}]`, the default crop
  for a card without one.
  """
  def avatar_cards_with_crops(format_id) do
    default = Avatars.default_crop()

    Repo.all(
      from fa in FormatAvatarCard,
        join: c in Card,
        on: c.id == fa.card_id,
        left_join: cr in CardAvatarCrop,
        on: cr.card_id == c.id,
        where: fa.format_id == ^format_id,
        order_by: [asc: fa.position, asc: fa.id],
        select: {struct(c, [:id, :name, :password]), cr}
    )
    |> Enum.map(fn {card, row} -> %{card: card, crop: crop_of(row, default)} end)
  end

  @doc "The crop of the card, `Avatars.default_crop/0` when none is stored."
  def avatar_crop(card_id) when is_integer(card_id) do
    crop_of(Repo.get(CardAvatarCrop, card_id), Avatars.default_crop())
  end

  @doc """
  The crops of the card pictures among `slugs` (any strings; slugs that are not
  card slugs are ignored) with one query: `%{slug => %{x, y, zoom}}` for the
  card slugs that have a stored crop. With `defaults: true` every card slug is
  in the map, `Avatars.default_crop/0` for those without a stored crop (also
  for cards that do not exist).
  """
  def avatar_crops(slugs, opts \\ []) do
    by_id =
      slugs
      |> Enum.flat_map(fn slug -> if id = Avatars.card_id(slug), do: [{id, slug}], else: [] end)
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))

    stored =
      if by_id == %{} do
        %{}
      else
        ids = Map.keys(by_id)
        Map.new(Repo.all(from cr in CardAvatarCrop, where: cr.card_id in ^ids), &{&1.card_id, &1})
      end

    default = if Keyword.get(opts, :defaults, false), do: Avatars.default_crop()

    for {id, slugs} <- by_id,
        crop = crop_of(stored[id], default),
        slug <- slugs,
        into: %{},
        do: {slug, crop}
  end

  defp crop_of(nil, default), do: default
  defp crop_of(row, _default), do: %{x: row.x, y: row.y, zoom: row.zoom}

  @doc """
  Stores the crop `%{x:, y:, zoom:}` of the card (integers: `x`, `y` 0..100,
  `zoom` 100..300; the caller converts form input). Replaces a stored crop; the
  default crop deletes the row instead, as a card without a row has it.

  Returns `{:ok, %{x, y, zoom}}`, `{:error, :invalid}` or `{:error, :not_found}`
  (no such card).
  """
  def set_avatar_crop(card_id, %{x: x, y: y, zoom: zoom})
      when is_integer(x) and is_integer(y) and is_integer(zoom) and x in 0..100 and
             y in 0..100 and zoom in 100..300 do
    crop = %{x: x, y: y, zoom: zoom}

    cond do
      not (is_integer(card_id) and card_id in 1..9_223_372_036_854_775_807//1) ->
        {:error, :not_found}

      not Repo.exists?(from c in Card, where: c.id == ^card_id) ->
        {:error, :not_found}

      crop == Avatars.default_crop() ->
        reset_avatar_crop(card_id)
        {:ok, crop}

      true ->
        Repo.insert!(struct!(CardAvatarCrop, Map.put(crop, :card_id, card_id)),
          on_conflict: [set: Map.to_list(crop)],
          conflict_target: :card_id
        )

        {:ok, crop}
    end
  rescue
    # the card was deleted between the check and the insert
    Ecto.ConstraintError -> {:error, :not_found}
  end

  def set_avatar_crop(_card_id, _crop), do: {:error, :invalid}

  @doc "Deletes the stored crop of the card (it has the default again). Always `:ok`."
  def reset_avatar_crop(card_id) do
    Repo.delete_all(from cr in CardAvatarCrop, where: cr.card_id == ^card_id)
    :ok
  end

  ## Questions

  @doc "The question with this id (topic preloaded), or nil (also for ids that aren't valid)."
  def get_question(id) do
    case Ecto.Type.cast(:id, id) do
      {:ok, id} -> Question |> Repo.get(id) |> Repo.preload(:topic)
      :error -> nil
    end
  end

  def get_question!(id) do
    Question |> Repo.get!(id) |> Repo.preload([:topic, question_cards: [card: :card_texts]])
  end

  def get_topic!(id), do: Topic |> Repo.get!(id) |> Repo.preload(:format)

  @doc "Position a new question gets: the end of the list, i.e. the hardest."
  def next_question_position(%Topic{} = topic) do
    Repo.one(from q in Question, where: q.topic_id == ^topic.id, select: count(q.id))
  end

  @doc """
  Creates a question at the end of the topic. `cards` sets the cards the
  question is about, in display order: card pool ids, or `{id, owner}` with the
  owner 1, 2 or nil (see `Question.put_cards/2`).
  """
  def create_question(%Topic{} = topic, attrs, cards \\ []) do
    %Question{topic_id: topic.id, position: next_question_position(topic), question_cards: []}
    |> Question.changeset(attrs)
    |> Question.put_cards(cards)
    |> Repo.insert()
  end

  def update_question(%Question{} = question, attrs, cards \\ nil) do
    question
    |> Repo.preload(:question_cards)
    |> Question.changeset(attrs)
    |> then(&if(cards, do: Question.put_cards(&1, cards), else: &1))
    |> Repo.update()
  end

  def delete_question(%Question{} = question) do
    Repo.transaction(fn ->
      Repo.delete!(question)
      renumber_questions(question.topic_id)
    end)
  end

  def change_question(%Question{} = question, attrs \\ %{}) do
    Question.changeset(question, attrs)
  end

  @doc """
  Moves a question one step easier (`:up`) or harder (`:down`) by swapping
  it with its neighbour. Default points follow automatically.
  """
  def move_question(%Question{} = question, direction) when direction in [:up, :down] do
    Repo.transaction(fn ->
      ids =
        Repo.all(
          from q in Question,
            where: q.topic_id == ^question.topic_id,
            order_by: [asc: q.position, asc: q.id],
            select: q.id,
            lock: "FOR UPDATE"
        )

      index = Enum.find_index(ids, &(&1 == question.id))
      target = if direction == :up, do: index - 1, else: index + 1

      ids =
        if target in 0..(length(ids) - 1)//1 do
          ids
          |> List.replace_at(index, Enum.at(ids, target))
          |> List.replace_at(target, question.id)
        else
          ids
        end

      write_positions(ids)
    end)
  end

  defp renumber_questions(topic_id) do
    Repo.all(
      from q in Question,
        where: q.topic_id == ^topic_id,
        order_by: [asc: q.position, asc: q.id],
        select: q.id
    )
    |> write_positions()
  end

  defp write_positions(ids) do
    ids
    |> Enum.with_index()
    |> Enum.each(fn {id, position} ->
      Repo.update_all(from(q in Question, where: q.id == ^id), set: [position: position])
    end)
  end

  @doc "All questions of a format with their topic and cards, used to build a game."
  def questions_for_format(format_id) do
    Repo.all(
      from q in Question,
        join: t in assoc(q, :topic),
        where: t.format_id == ^format_id,
        preload: [topic: t, question_cards: [card: :card_texts]]
    )
  end

  ## Suggested questions

  # Unreviewed submissions that are kept; over it, new ones are refused so a
  # flood cannot fill the database.
  @max_pending_submissions 200

  def max_pending_submissions, do: @max_pending_submissions

  @doc "Formats with their topics, for the suggestion form's pickers."
  def list_formats_with_topics do
    Repo.all(from f in Format, order_by: f.name, preload: [:topics])
  end

  @doc """
  Stores a player's suggestion for `topic`. Returns `{:error, :full}` when
  `max_pending_submissions/0` are already waiting.
  """
  def create_submission(%Topic{} = topic, attrs) do
    if count_submissions(:pending) >= @max_pending_submissions do
      {:error, :full}
    else
      %Submission{topic_id: topic.id, token: new_token(), choices: []}
      |> Submission.changeset(attrs)
      |> Repo.insert()
    end
  end

  def change_submission(%Submission{} = submission, attrs \\ %{}),
    do: Submission.changeset(submission, attrs)

  defp new_token, do: :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)

  def get_submission(id) do
    case Ecto.Type.cast(:id, id) do
      {:ok, id} -> Submission |> Repo.get(id) |> Repo.preload(topic: :format)
      :error -> nil
    end
  end

  @doc "The submission with this private token, or nil."
  def get_submission_by_token(token) when is_binary(token) do
    Submission |> Repo.get_by(token: token) |> Repo.preload(topic: :format)
  end

  @doc "Submissions with this status (or all with `:all`), oldest pending first, newest otherwise."
  def list_submissions(status) do
    base = from s in Submission, preload: [topic: :format]

    case status do
      :pending ->
        from s in base, where: s.status == "pending", order_by: [asc: s.inserted_at, asc: s.id]

      :all ->
        from s in base, order_by: [desc: s.inserted_at, desc: s.id]

      status ->
        from s in base,
          where: s.status == ^to_string(status),
          order_by: [desc: s.inserted_at, desc: s.id]
    end
    |> Repo.all()
  end

  def count_submissions(status) do
    Repo.one(from s in Submission, where: s.status == ^to_string(status), select: count(s.id))
  end

  @doc """
  Creates the question an admin made from a pending submission and marks the
  submission approved, in one transaction. A submission that was reviewed in
  the meantime (another admin) is refused with `{:error, :reviewed}`.
  """
  def approve_submission(%Submission{id: id}, %Topic{} = topic, attrs, cards) do
    Repo.transaction(fn ->
      submission = Repo.one!(from s in Submission, where: s.id == ^id, lock: "FOR UPDATE")

      if submission.status != "pending" do
        Repo.rollback(:reviewed)
      else
        case create_question(topic, attrs, cards) do
          {:ok, question} ->
            submission
            |> Ecto.Changeset.change(
              status: "approved",
              question_id: question.id,
              reviewed_at: now()
            )
            |> Repo.update!()

            question

          {:error, changeset} ->
            Repo.rollback(changeset)
        end
      end
    end)
  end

  @doc "Marks a pending submission rejected; it is kept."
  def reject_submission(%Submission{id: id}) do
    {count, _} =
      Repo.update_all(
        from(s in Submission, where: s.id == ^id and s.status == "pending"),
        set: [status: "rejected", reviewed_at: now()]
      )

    if count == 1, do: :ok, else: {:error, :reviewed}
  end

  def delete_submission(%Submission{} = submission), do: Repo.delete(submission)

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
