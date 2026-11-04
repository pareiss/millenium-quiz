defmodule MillenniumQuiz.Quiz.PackImport do
  @moduledoc """
  Imports a pack of questions into an **existing** format (puzzle PR P2).

  A pack is the JSON that the authoring tool writes: the backup file's topic
  shape without the format around it.

      {"version": 1,
       "credits": "optional text, shown in the report",
       "topics": [
         {"name": "Next play: GX B08",
          "questions": [
            {"text": "...", "choices": [{"text": "...", "correct": true}, ...],
             "cards": [{"password": 123, "owner": 1}],
             "board": { ... board.v1 ... }}]}]}

  Every question is multiple choice with exactly one correct answer, like any
  other; `board` and `cards` are optional.

    * The pack as a whole is rejected (nothing is created) only when it is not
      JSON, too large or not a pack (version, topics, names, sizes).
    * Each question is judged on its own. One that fails is listed in
      `failed` with its topic, number, text and the reason, and the others are
      still imported. A question fails for a text or choice rule, for a
      `board` that is not an object or does not cast, or that does not pass
      `Board.validate/2` on the format's date (a card missing from the pool
      after the fetch, a card released later, a zone the Master Rule lacks).
      A question whose board is invalid is **not** imported without it: in a
      puzzle the board is the question.
    * Topics are matched by name (case-insensitive) with the topics of the
      format; their questions are appended after the existing ones (the
      hardest end). A topic that is not there is created, as long as the
      format has fewer than `Format.max_topics/0`; a topic left without any
      imported question is not created.
    * A question that the topic already has (same identity, see `duplicate?/3`) is
      counted in `skipped`, so importing a pack twice adds nothing. The text is
      compared without the `[card]` brackets and card names, so it does not
      matter whether a card was fetched or renamed between two imports.
    * Two imports into the same format never run their writes at the same time
      (an advisory lock on the format); the second waits up to `:lock_timeout_ms`
      (30 s) and then fails with "Another import into this format is running".
    * Cards the pool lacks are fetched like in `Import`: one at a time with a
      pause, before anything is written. A question card that cannot be
      fetched is unlinked with a warning (as in `Import`).
    * The format, its date and its other topics are never changed, and
      neither is a running game (games keep their own snapshot).

  `run/3` returns `{:ok, report}` or `{:error, message}`. Options: `:pause_ms`.
  """
  import Ecto.Query, only: [from: 2]

  alias MillenniumQuiz.{Quiz, Repo}
  alias MillenniumQuiz.Quiz.{Board, Format, Import, Topic}

  @max_topics 20
  @max_questions 200
  @max_total 500
  @max_credits 2_000
  @lock_timeout_ms 30_000
  @lock_poll_ms 100
  # first key of the two-key advisory lock; the second is the format id
  @lock_namespace 7_301

  @type failure :: %{topic: String.t(), number: pos_integer, text: String.t(), reason: String.t()}

  @type report :: %{
          imported: non_neg_integer,
          boards: non_neg_integer,
          skipped: non_neg_integer,
          topics_created: [String.t()],
          failed: [failure],
          warnings: [String.t()],
          credits: String.t() | nil
        }

  @spec run(%Format{} | pos_integer, binary | map, keyword) ::
          {:ok, report} | {:error, String.t()}
  def run(format, input, opts \\ [])

  def run(%Format{id: id}, input, opts), do: run(id, input, opts)

  def run(format_id, json, opts) when is_binary(json) do
    if byte_size(json) > Import.max_bytes() do
      {:error, "The file is too large (more than #{div(Import.max_bytes(), 1_000_000)} MB)."}
    else
      case Jason.decode(json) do
        {:ok, data} -> run(format_id, data, opts)
        {:error, _} -> {:error, "The file is not valid JSON."}
      end
    end
  end

  def run(format_id, %{} = data, opts) when is_integer(format_id) do
    with {:ok, pack} <- parse(data) do
      format = Quiz.get_format!(format_id)
      pause = Keyword.get_lazy(opts, :pause_ms, &Import.default_pause/0)
      lock_ms = Keyword.get(opts, :lock_timeout_ms, @lock_timeout_ms)
      import_pack(format, pack, pause, lock_ms)
    end
  end

  def run(_format, _other, _opts), do: {:error, "The file must contain a JSON object."}

  ## Structure of the pack (a failure here rejects the pack)

  defp parse(%{"version" => 1, "topics" => topics} = data) when is_list(topics) do
    with {:ok, credits} <- credits(data["credits"]),
         :ok <- size(topics),
         {:ok, topics} <- parse_topics(topics),
         :ok <- merged_size(topics) do
      {:ok, %{credits: credits, topics: topics}}
    end
  end

  defp parse(%{"version" => 1}), do: {:error, "The pack has no list of topics."}

  defp parse(%{"version" => v}),
    do: {:error, "Unsupported pack version #{inspect(v)} (expected 1)."}

  defp parse(_), do: {:error, "This is not a question pack (no version)."}

  defp credits(nil), do: {:ok, nil}

  defp credits(c) when is_binary(c) and byte_size(c) <= @max_credits, do: {:ok, c}

  defp credits(_), do: {:error, "credits must be text of at most #{@max_credits} bytes."}

  defp size(topics) do
    cond do
      topics == [] ->
        {:error, "The pack has no topics."}

      length(topics) > @max_topics ->
        {:error, "Too many topics (at most #{@max_topics})."}

      total(topics) > @max_total ->
        {:error, "Too many questions (at most #{@max_total})."}

      true ->
        :ok
    end
  end

  # Entries with the same name are one topic, so the limit counts the merged one.
  defp merged_size(topics) do
    if Enum.any?(topics, &(length(&1.raw) > @max_questions)),
      do: {:error, "Too many questions in a topic (at most #{@max_questions})."},
      else: :ok
  end

  defp total(topics) do
    topics
    |> Enum.map(
      &if(is_map(&1) and is_list(&1["questions"]), do: length(&1["questions"]), else: 0)
    )
    |> Enum.sum()
  end

  defp parse_topics(topics) do
    topics
    |> Enum.with_index(1)
    |> Enum.reduce_while({:ok, []}, fn
      {%{"name" => name, "questions" => questions}, _i}, {:ok, acc}
      when is_binary(name) and is_list(questions) ->
        if String.trim(name) == "" or byte_size(name) > 5_000 do
          {:halt, {:error, "A topic needs a name."}}
        else
          {:cont, {:ok, [%{name: String.trim(name), raw: questions} | acc]}}
        end

      {_other, i}, _ ->
        {:halt, {:error, "Topic #{i}: needs a name and a list of questions."}}
    end)
    |> case do
      {:ok, acc} -> {:ok, merge_same_names(Enum.reverse(acc))}
      error -> error
    end
  end

  # Two entries with the same name (any case) are one topic; the question
  # numbers of the report keep counting through the pack's entries in order.
  defp merge_same_names(topics) do
    Enum.reduce(topics, [], fn topic, acc ->
      key = key(topic.name)

      case Enum.find_index(acc, &(key(&1.name) == key)) do
        nil -> acc ++ [topic]
        i -> List.update_at(acc, i, &%{&1 | raw: &1.raw ++ topic.raw})
      end
    end)
  end

  defp key(name), do: name |> String.trim() |> String.downcase()

  ## Judging the questions

  # Every question of a topic becomes {:ok, parsed} or {:error, reason}.
  defp judge(topic) do
    questions =
      topic.raw
      |> Enum.with_index(1)
      |> Enum.map(fn {raw, number} -> {number, raw, judge_question(raw)} end)

    Map.put(topic, :questions, questions)
  end

  defp judge_question(raw) do
    with {:ok, q} <- Import.question(raw),
         :ok <- no_board_error(q),
         :ok <- Import.check_question(q) do
      {:ok, q}
    end
  end

  defp no_board_error(%{board_error: nil}), do: :ok
  defp no_board_error(%{board_error: error}), do: {:error, "board: #{error}"}

  ## Writing

  # The cards are fetched first, without any lock (slow, and it touches no
  # format). Only the writes are serialised per format, so two imports cannot
  # create the same topic twice, exceed the topic limit or give two questions
  # one position. A session-level lock on one checked-out connection is used,
  # not `pg_advisory_xact_lock` in a transaction: the writes report problems
  # as `{:error, changeset}` and go on (e.g. a constraint violation of one
  # question), which would poison a surrounding Postgres transaction. The
  # lock is polled with `pg_try_advisory_lock` so that waiting is bounded, and
  # released in `after`; the connection is held only for the fast writes.
  defp import_pack(format, pack, pause, lock_ms) do
    topics = Enum.map(pack.topics, &judge/1)
    pool = fetch_pool(topics, format, pause)

    Repo.checkout(fn ->
      if acquire_lock(format.id, lock_ms) do
        try do
          {:ok, write(topics, format, pool, pack.credits)}
        after
          Repo.query!("SELECT pg_advisory_unlock($1, $2)", [@lock_namespace, format.id])
        end
      else
        {:error, "Another import into this format is running. Try again in a moment."}
      end
    end)
  end

  defp acquire_lock(format_id, ms_left) do
    %{rows: [[locked]]} =
      Repo.query!("SELECT pg_try_advisory_lock($1, $2)", [@lock_namespace, format_id])

    cond do
      locked ->
        true

      ms_left <= 0 ->
        false

      true ->
        Process.sleep(@lock_poll_ms)
        acquire_lock(format_id, ms_left - @lock_poll_ms)
    end
  end

  defp fetch_pool(topics, format, pause) do
    topics
    |> Enum.flat_map(& &1.questions)
    |> Enum.flat_map(fn
      {_n, _raw, {:ok, q}} -> passwords(q, format.date)
      _ -> []
    end)
    |> Enum.uniq()
    |> Import.resolve(%{pool: %{}, fetches: 0}, pause)
    |> Map.fetch!(:pool)
  end

  defp write(topics, format, pool, credits) do
    empty = %{
      imported: 0,
      boards: 0,
      skipped: 0,
      topics_created: [],
      failed: [],
      warnings: [],
      credits: credits
    }

    report = Enum.reduce(topics, empty, &import_topic(&1, format, pool, &2))

    %{
      report
      | topics_created: Enum.reverse(report.topics_created),
        failed: Enum.reverse(report.failed),
        warnings: Enum.reverse(report.warnings)
    }
  end

  defp passwords(q, date) do
    board_missing =
      case q.board && Board.validate(q.board, date) do
        {:error, issues} -> Board.missing_passwords(issues)
        _ -> []
      end

    Enum.map(q.cards, & &1.password) ++ board_missing
  end

  # The failures of one topic are listed in question order, whichever step
  # (judging, board re-check, insert) found them.
  defp import_topic(topic, format, pool, report) do
    earlier = report.failed
    report = do_import_topic(topic, format, pool, %{report | failed: []})
    in_order = Enum.sort_by(report.failed, & &1.number, :desc)
    %{report | failed: in_order ++ earlier}
  end

  defp do_import_topic(topic, format, pool, report) do
    {valid, invalid} =
      Enum.split_with(topic.questions, &match?({_, _, {:ok, _}}, &1))

    report = Enum.reduce(invalid, report, &fail(&2, topic.name, &1))

    cond do
      valid == [] ->
        report

      true ->
        case find_or_create_topic(format, topic.name) do
          {:ok, db_topic, created?} ->
            report = if created?, do: add(report, :topics_created, topic.name), else: report

            report =
              Enum.reduce(valid, report, &create(&2, format, db_topic, topic.name, pool, &1))

            drop_if_empty(db_topic, created?, report)

          {:error, reason} ->
            Enum.reduce(valid, report, fn {number, raw, _}, acc ->
              fail(acc, topic.name, {number, raw, {:error, reason}})
            end)
        end
    end
  end

  # A topic that this import created and that got no question (all failed or
  # skipped) is not left behind.
  defp drop_if_empty(db_topic, true, report) do
    if Repo.exists?(from q in Quiz.Question, where: q.topic_id == ^db_topic.id) do
      report
    else
      Repo.delete!(db_topic)
      %{report | topics_created: List.delete(report.topics_created, db_topic.name)}
    end
  end

  defp drop_if_empty(_db_topic, false, report), do: report

  defp find_or_create_topic(format, name) do
    topics = Repo.all(from t in Topic, where: t.format_id == ^format.id, order_by: t.position)
    wanted = key(name)

    full? = length(topics) >= Format.max_topics()

    case Enum.find(topics, &(key(&1.name) == wanted)) do
      %Topic{} = topic ->
        {:ok, topic, false}

      nil when full? ->
        {:error,
         "the format already has #{Format.max_topics()} topics, so topic \"#{name}\" cannot be added"}

      nil ->
        position = (topics |> Enum.map(& &1.position) |> Enum.max(fn -> -1 end)) + 1

        %Topic{format_id: format.id}
        |> Topic.changeset(%{"name" => name}, position)
        |> Repo.insert()
        |> case do
          {:ok, topic} -> {:ok, topic, true}
          {:error, cs} -> {:error, "topic: " <> Import.errors(cs)}
        end
    end
  end

  defp create(report, format, db_topic, topic_name, pool, {number, raw, {:ok, q}}) do
    {entries, text, warnings, _missing} =
      Import.link_cards(q, pool, format.name, topic_name, number)

    # The board is judged again now that the cards are fetched, and so are the
    # cards of the question (the admin form refuses a card released after the
    # format's date, so an import must too).
    case problem(q, format.date) do
      {:error, reason} ->
        fail(report, topic_name, {number, raw, {:error, reason}})

      :ok ->
        if duplicate?(db_topic, q, pool) do
          %{report | skipped: report.skipped + 1}
        else
          attrs = %{
            "text" => text,
            "submitted_by" => q.submitted_by,
            "choices" => q.choices,
            "board" => q.board
          }

          case Quiz.create_question(db_topic, attrs, entries) do
            {:ok, _} ->
              %{
                report
                | imported: report.imported + 1,
                  boards: report.boards + if(q.board, do: 1, else: 0),
                  warnings: Enum.reverse(warnings, report.warnings)
              }

            {:error, cs} ->
              fail(report, topic_name, {number, raw, {:error, Import.errors(cs)}})
          end
        end
    end
  end

  defp problem(q, date) do
    with {:board, :ok} <- {:board, if(q.board, do: Board.validate(q.board, date), else: :ok)},
         :ok <- check_released(q.cards, date) do
      :ok
    else
      {:board, {:error, issues}} -> {:error, "board: " <> Import.issues_text(issues)}
      {:error, _} = error -> error
    end
  end

  # Same rule as the admin form's `released_by?/2`: a card released after the
  # format's date is refused; a card without a release date, or a format
  # without a date, is not checked.
  defp check_released(_cards, nil), do: :ok

  defp check_released(cards, date) do
    passwords = Enum.map(cards, & &1.password)

    Repo.all(
      from c in MillenniumQuiz.Cards.Card,
        where: c.password in ^passwords and c.tcg_release_date > ^date,
        order_by: c.name,
        select: {c.name, c.password, c.tcg_release_date}
    )
    |> case do
      [] ->
        :ok

      late ->
        {:error,
         "cards: " <>
           Enum.map_join(late, "; ", fn {name, pw, released} ->
             "#{name} (#{pw}) was released on #{released}, after the format's date #{date}"
           end)}
    end
  end

  # Identity of a question: everything that makes it a different question,
  # computed in ONE place (`identity/4`) for the pack question and for each
  # stored one, and compared as a hash. A new field that matters is added there.
  #
  #   * the canonical text: `[`/`]` removed, every name of a card of the question
  #     (pack, pool now, stored) replaced by a placeholder tied to the card's
  #     password, matched case-insensitively and as whole names only; the rest of
  #     the text is compared exactly (case included);
  #   * the choices in order, with the correct flag;
  #   * the board;
  #   * the ordered list of `{card password, owner}`.
  #
  # The match must not depend on how the cards resolved: a card that could not
  # be fetched the first time is unlinked (`Ghost`, no card row), the retry links
  # it (`[Ghost]`), and a card may have been renamed in between. So a card of
  # the pack that the stored question does not have attached is left out of the
  # comparison when it has a name and that name stands in the stored text (that
  # is how an unlinked card looks). A pack card without a name that was never
  # linked cannot be recognised and counts as a difference.
  defp duplicate?(db_topic, q, pool) do
    pack_names = pack_names(q, pool)

    from(x in Quiz.Question,
      where: x.topic_id == ^db_topic.id,
      preload: [question_cards: :card]
    )
    |> Repo.all()
    |> Enum.any?(fn x ->
      stored_cards = Enum.filter(x.question_cards, &(&1.card && is_binary(&1.card.name)))
      stored_names = for %{card: %{name: name, password: pw}} <- stored_cards, do: {name, pw}
      stored_pws = MapSet.new(stored_names, &elem(&1, 1))
      names = pack_names ++ stored_names

      pack_cards =
        q.cards
        # `Question.put_cards/2` keeps the first entry of a card listed twice
        |> Enum.uniq_by(& &1.password)
        |> Enum.reject(fn card ->
          not MapSet.member?(stored_pws, card.password) and
            unlinked_in?(x.text, card, pack_names)
        end)
        |> Enum.map(&{&1.password, &1.owner})

      stored = Enum.map(x.question_cards, &{&1.card && &1.card.password, &1.owner})

      identity(
        q.text,
        Enum.map(q.choices, &{&1["text"], &1["correct"]}),
        q.board,
        pack_cards,
        names
      ) ==
        identity(
          x.text,
          Enum.map(x.choices, &{&1.text, &1.correct}),
          x.board,
          stored,
          names
        )
    end)
  end

  defp identity(text, choices, board, cards, names) do
    :crypto.hash(
      :sha256,
      :erlang.term_to_binary({canonical(text, names), choices, board, cards})
    )
  end

  # Does the stored text mention a name of this pack card as plain text?
  defp unlinked_in?(text, card, pack_names) do
    pack_names
    |> Enum.filter(fn {_name, pw} -> pw == card.password end)
    |> Enum.any?(fn {name, _} -> Regex.match?(name_regex(name), text) end)
  end

  # `{name, password}` of every name a card of the pack question may have.
  defp pack_names(q, pool) do
    Enum.flat_map(q.cards, fn card ->
      current =
        case Map.get(pool, card.password) do
          {:ok, _id, name} -> [{name, card.password}]
          _ -> []
        end

      Enum.map(List.wrap(card.name), &{&1, card.password}) ++ current
    end)
  end

  # Whole names only, never a piece of another word; case-insensitive.
  defp name_regex(name),
    do: ~r/(?<![\p{L}\p{N}])#{Regex.escape(String.trim(name))}(?![\p{L}\p{N}])/iu

  defp canonical(text, names) do
    names =
      names
      |> Enum.map(fn {name, pw} -> {String.trim(name), pw} end)
      |> Enum.reject(fn {name, _} -> name == "" end)
      |> Enum.uniq_by(fn {name, pw} -> {String.downcase(name), pw} end)
      |> Enum.sort_by(fn {name, _} -> String.length(name) end, :desc)

    Enum.reduce(names, String.replace(text, ["[", "]"], ""), fn {name, pw}, acc ->
      Regex.replace(name_regex(name), acc, "\0#{pw}\0")
    end)
  end

  defp fail(report, topic_name, {number, raw, {:error, reason}}) do
    failure = %{
      topic: topic_name,
      number: number,
      text: raw |> raw_text() |> String.slice(0, 80),
      reason: reason
    }

    %{report | failed: [failure | report.failed]}
  end

  defp raw_text(%{"text" => text}) when is_binary(text), do: text
  defp raw_text(_), do: ""

  defp add(report, :topics_created, name),
    do: %{report | topics_created: [name | report.topics_created]}

  @doc "The report as lines of text, for the admin page and the server log."
  @spec report_lines(report) :: [String.t()]
  def report_lines(r) do
    [
      "Questions imported: #{r.imported} (#{r.boards} with a board), already there: #{r.skipped}, failed: #{length(r.failed)}"
    ] ++
      if(r.topics_created == [],
        do: [],
        else: ["Topics created: " <> Enum.join(r.topics_created, ", ")]
      ) ++
      Enum.map(r.failed, &"Failed: #{&1.topic}, question #{&1.number}: #{&1.reason}") ++
      Enum.map(r.warnings, &"Warning: #{&1}")
  end
end
