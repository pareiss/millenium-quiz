defmodule MillenniumQuiz.Quiz.Import do
  @moduledoc """
  Restores a backup made by `MillenniumQuiz.Quiz.Export`.

  The whole file is validated first (version, types, sizes, counts); a file
  that fails is rejected as a whole and nothing is created. Then each format
  is created in its own transaction, through the normal changesets, so every
  domain rule still applies: a format that breaks one is reported in
  `failed` and creates nothing, the others are not affected.

    * A format whose name already exists is skipped (`skipped`), never
      overwritten, so importing a file twice is harmless.
    * Card links: the card of the pool is used, else it is fetched with
      `Cards.import/1` (one at a time, with a pause) before the format's
      transaction starts. When that fails the question is still created
      without that link and a warning says so. The `[Card Name]` marker of the
      text is then unlinked (brackets removed, as `CardLinks.unlink/2`), so no
      marker is left that points at nothing. When the card has another name now
      than in the file (renamed since the export), the marker is rewritten to
      the current name so it still links, and a warning says so.

  `run/2` returns `{:ok, summary}` or `{:error, message}`. Options:
  `:pause_ms` (pause between remote card fetches, default as
  `Cards.refresh_all/0`).
  """
  import Ecto.Query, only: [from: 2]

  alias MillenniumQuiz.{Cards, Quiz, Repo}
  alias MillenniumQuiz.Cards.Card
  alias MillenniumQuiz.Quiz.{CardLinks, Choice, Export, Format, Question}

  @max_bytes 5_000_000
  @max_formats 50
  @max_topics 20
  @max_questions 200
  @max_choices 20
  @max_cards 20
  @max_string 5_000

  def max_bytes, do: @max_bytes

  @type summary :: %{
          formats_created: non_neg_integer,
          formats_skipped: [String.t()],
          formats_failed: [{String.t(), String.t()}],
          topics: non_neg_integer,
          questions: non_neg_integer,
          cards_linked: non_neg_integer,
          cards_missing: non_neg_integer,
          avatars: non_neg_integer,
          avatars_missing: non_neg_integer,
          warnings: [String.t()]
        }

  @spec run(binary | map, keyword) :: {:ok, summary} | {:error, String.t()}
  def run(input, opts \\ [])

  def run(json, opts) when is_binary(json) do
    if byte_size(json) > @max_bytes do
      {:error, "The file is too large (more than #{div(@max_bytes, 1_000_000)} MB)."}
    else
      case Jason.decode(json) do
        {:ok, data} -> run(data, opts)
        {:error, _} -> {:error, "The file is not valid JSON."}
      end
    end
  end

  def run(%{} = data, opts) do
    with {:ok, formats} <- validate(data) do
      pause = Keyword.get_lazy(opts, :pause_ms, &default_pause/0)
      {:ok, import_formats(formats, pause)}
    end
  end

  def run(_other, _opts), do: {:error, "The file must contain a JSON object."}

  defp default_pause do
    Application.get_env(:millennium_quiz, Cards, [])[:refresh_pause_ms] || 250
  end

  ## Validation (structure only; the changesets decide the domain rules)

  defp validate(%{"version" => 1, "formats" => formats}) when is_list(formats) do
    cond do
      length(formats) > @max_formats ->
        {:error, "Too many formats (at most #{@max_formats})."}

      true ->
        formats
        |> Enum.with_index(1)
        |> Enum.reduce_while({:ok, []}, fn {f, i}, {:ok, acc} ->
          case format(f) do
            {:ok, f} -> {:cont, {:ok, [f | acc]}}
            {:error, msg} -> {:halt, {:error, "Format #{i}: #{msg}"}}
          end
        end)
        |> case do
          {:ok, acc} -> {:ok, Enum.reverse(acc)}
          error -> error
        end
    end
  end

  defp validate(%{"version" => 1}), do: {:error, "The file has no list of formats."}

  defp validate(%{"version" => v}),
    do: {:error, "Unsupported backup version #{inspect(v)} (expected #{Export.version()})."}

  defp validate(_), do: {:error, "This is not a Millennium Quiz backup (no version)."}

  defp format(%{"name" => name, "date" => date, "topics" => topics} = f) when is_list(topics) do
    with :ok <- text(name, "name"),
         :ok <- optional_text(f["description"], "description"),
         {:ok, date} <- date(date),
         :ok <- count(topics, @max_topics, "topics"),
         {:ok, topics} <- each(topics, &topic/1, "topic"),
         {:ok, avatars} <- avatar_cards(Map.get(f, "avatar_cards")) do
      {:ok,
       %{name: name, description: f["description"], date: date, topics: topics, avatars: avatars}}
    else
      {:error, msg} -> {:error, "#{label(name)}#{msg}"}
    end
  end

  defp format(_), do: {:error, "needs a name, a date and a list of topics."}

  # Optional (older backups have none).
  defp avatar_cards(nil), do: {:ok, []}

  defp avatar_cards(cards) when is_list(cards) do
    with :ok <- count(cards, Quiz.max_avatar_cards(), "avatar cards"),
         do: each(cards, &avatar_card/1, "avatar card")
  end

  defp avatar_cards(_), do: {:error, "avatar_cards must be a list."}

  # A card with an optional "crop"; a crop that is not valid is remembered as
  # :invalid and costs a warning later, not the file.
  defp avatar_card(c) do
    with {:ok, card} <- card(c), do: {:ok, Map.put(card, :crop, crop(c["crop"]))}
  end

  defp crop(nil), do: nil

  defp crop(%{"x" => x, "y" => y, "zoom" => zoom} = c) when map_size(c) == 3 do
    crop = %{x: x, y: y, zoom: zoom}
    if valid_crop?(crop), do: crop, else: :invalid
  end

  defp crop(_), do: :invalid

  defp valid_crop?(%{x: x, y: y, zoom: zoom}),
    do:
      is_integer(x) and is_integer(y) and is_integer(zoom) and x in 0..100 and y in 0..100 and
        zoom in 100..300

  defp label(name) when is_binary(name), do: "\"#{String.slice(name, 0, 40)}\": "
  defp label(_), do: ""

  defp topic(%{"name" => name, "questions" => questions}) when is_list(questions) do
    with :ok <- text(name, "name"),
         :ok <- count(questions, @max_questions, "questions"),
         {:ok, questions} <- each(questions, &question/1, "question") do
      {:ok, %{name: name, questions: questions}}
    end
  end

  defp topic(_), do: {:error, "needs a name and a list of questions."}

  defp question(%{"text" => text, "choices" => choices} = q) when is_list(choices) do
    cards = Map.get(q, "cards") || []
    submitted_by = Map.get(q, "submitted_by")

    with :ok <- text(text, "text"),
         :ok <- optional_text(submitted_by, "submitted_by"),
         :ok <- legacy_points(Map.get(q, "points")),
         :ok <- count(choices, @max_choices, "choices"),
         {:ok, choices} <- each(choices, &choice/1, "choice"),
         true <- is_list(cards) or {:error, "cards must be a list."},
         :ok <- count(cards, @max_cards, "cards"),
         {:ok, cards} <- each(cards, &card/1, "card") do
      {:ok,
       %{
         text: text,
         submitted_by: submitted_by,
         choices: choices,
         cards: cards
       }}
    end
  end

  defp question(_), do: {:error, "needs a text and a list of choices."}

  defp choice(%{"text" => text, "correct" => correct}) when is_boolean(correct) do
    with :ok <- text(text, "text"), do: {:ok, %{"text" => text, "correct" => correct}}
  end

  defp choice(_), do: {:error, "needs a text and a true/false \"correct\"."}

  defp card(%{"password" => password} = c) when is_integer(password) and password > 0 do
    with :ok <- optional_text(c["name"], "name"),
         :ok <- owner(c["owner"]),
         do: {:ok, %{password: password, name: c["name"], owner: c["owner"]}}
  end

  defp card(_), do: {:error, "needs a positive integer \"password\"."}

  defp owner(owner) when owner in [nil, 1, 2], do: :ok
  defp owner(_), do: {:error, "\"owner\" must be 1, 2 or null."}

  # Old backups carry a per-question "points" (null or a whole number). Games no
  # longer use it: it is checked as before and then dropped.
  defp legacy_points(nil), do: :ok
  defp legacy_points(p) when is_integer(p), do: :ok
  defp legacy_points(_), do: {:error, "points must be a whole number or null."}

  defp date(date) when is_binary(date) do
    case Date.from_iso8601(date) do
      {:ok, d} -> {:ok, d}
      _ -> {:error, "the date must look like 2010-03-01."}
    end
  end

  defp date(_), do: {:error, "the date must look like 2010-03-01."}

  defp text(s, _what) when is_binary(s) and byte_size(s) <= @max_string, do: :ok
  defp text(_, what), do: {:error, "#{what} must be text of at most #{@max_string} bytes."}

  defp optional_text(nil, _), do: :ok
  defp optional_text(s, what), do: text(s, what)

  defp count(list, max, what) do
    if length(list) > max, do: {:error, "too many #{what} (at most #{max})."}, else: :ok
  end

  defp each(list, fun, what) do
    list
    |> Enum.with_index(1)
    |> Enum.reduce_while({:ok, []}, fn {item, i}, {:ok, acc} ->
      case fun.(item) do
        {:ok, v} -> {:cont, {:ok, [v | acc]}}
        {:error, msg} -> {:halt, {:error, "#{what} #{i}: #{msg}"}}
      end
    end)
    |> case do
      {:ok, acc} -> {:ok, Enum.reverse(acc)}
      error -> error
    end
  end

  ## Import

  @empty %{
    formats_created: 0,
    formats_skipped: [],
    formats_failed: [],
    topics: 0,
    questions: 0,
    cards_linked: 0,
    cards_missing: 0,
    avatars: 0,
    avatars_missing: 0,
    warnings: []
  }

  defp import_formats(formats, pause) do
    {summary, _cards} =
      Enum.reduce(formats, {@empty, %{pool: %{}, fetches: 0}}, fn format, {summary, cards} ->
        import_format(format, summary, cards, pause)
      end)

    %{
      summary
      | formats_skipped: Enum.reverse(summary.formats_skipped),
        formats_failed: Enum.reverse(summary.formats_failed),
        warnings: Enum.reverse(summary.warnings)
    }
  end

  defp import_format(format, summary, cards, pause) do
    if Repo.exists?(from f in Quiz.Format, where: f.name == ^format.name) do
      {%{summary | formats_skipped: [format.name | summary.formats_skipped]}, cards}
    else
      with :ok <- check_domain(format) do
        import_checked(format, summary, cards, pause)
      else
        {:error, msg} ->
          {%{summary | formats_failed: [{format.name, msg} | summary.formats_failed]}, cards}
      end
    end
  end

  # The domain rules that can be known without the database. The changesets
  # stay the authority; this only keeps a doomed format from fetching cards.
  defp check_domain(format) do
    cond do
      String.length(format.name) > Format.max_name_length() ->
        {:error, "format: name is too long (at most #{Format.max_name_length()} characters)"}

      length(format.topics) not in Format.min_topics()..Format.max_topics() ->
        {:error,
         "topics: a format needs between #{Format.min_topics()} and #{Format.max_topics()} topics"}

      true ->
        Enum.find_value(format.topics, :ok, &check_topic/1)
    end
  end

  defp check_topic(topic) do
    if String.length(topic.name) > Format.max_name_length() do
      {:error, "topic \"#{String.slice(topic.name, 0, 40)}\": name is too long"}
    else
      topic.questions
      |> Enum.with_index(1)
      |> Enum.find_value(fn {q, i} ->
        case check_question(q) do
          :ok -> nil
          {:error, msg} -> {:error, "topic \"#{topic.name}\", question #{i}: #{msg}"}
        end
      end)
    end
  end

  defp check_question(q) do
    cond do
      is_binary(q.submitted_by) and
          String.length(q.submitted_by) > Question.max_submitter_length() ->
        {:error,
         "submitted_by is too long (at most #{Question.max_submitter_length()} characters)"}

      String.length(q.text) > Question.max_text_length() ->
        {:error, "text is too long (at most #{Question.max_text_length()} characters)"}

      length(q.choices) not in Question.min_choices()..Question.max_choices() ->
        {:error,
         "choices: between #{Question.min_choices()} and #{Question.max_choices()} are needed"}

      Enum.count(q.choices, & &1["correct"]) != 1 ->
        {:error, "choices: exactly one answer must be marked as correct"}

      Enum.any?(q.choices, &(String.length(&1["text"]) > Choice.max_text_length())) ->
        {:error, "a choice is too long (at most #{Choice.max_text_length()} characters)"}

      true ->
        :ok
    end
  end

  defp import_checked(format, summary, cards, pause) do
    passwords =
      format.topics
      |> Enum.flat_map(& &1.questions)
      |> Enum.flat_map(& &1.cards)
      |> Enum.concat(format.avatars)
      |> Enum.map(& &1.password)
      |> Enum.uniq()

    cards = resolve(passwords, cards, pause)

    case create(format, cards.pool) do
      {:ok, counts} ->
        {merge(summary, format, counts), cards}

      {:skip} ->
        {%{summary | formats_skipped: [format.name | summary.formats_skipped]}, cards}

      {:error, msg} ->
        {%{summary | formats_failed: [{format.name, msg} | summary.formats_failed]}, cards}
    end
  end

  defp merge(summary, format, counts) do
    %{
      summary
      | formats_created: summary.formats_created + 1,
        topics: summary.topics + length(format.topics),
        questions: summary.questions + counts.questions,
        cards_linked: summary.cards_linked + counts.linked,
        cards_missing: summary.cards_missing + counts.missing,
        avatars: summary.avatars + counts.avatars,
        avatars_missing: summary.avatars_missing + counts.avatars_missing,
        warnings: Enum.reverse(counts.warnings, summary.warnings)
    }
  end

  # Pool first; only what the pool lacks is fetched, one card at a time with
  # a pause (the sources are rate limited). Failures are remembered.
  defp resolve(passwords, state, pause) do
    Enum.reduce(passwords, state, fn password, %{pool: pool, fetches: fetches} = st ->
      cond do
        Map.has_key?(pool, password) ->
          st

        card = Repo.get_by(Card, password: password) ->
          %{st | pool: Map.put(pool, password, {:ok, card.id, card.name})}

        true ->
          if fetches > 0, do: Process.sleep(pause)
          %{st | pool: Map.put(pool, password, fetch(password)), fetches: fetches + 1}
      end
    end)
  end

  defp fetch(password) do
    case Cards.import(password) do
      {:ok, card} -> {:ok, card.id, card.name}
      {:error, reason} -> {:error, reason}
    end
  rescue
    e -> {:error, e}
  end

  defp create(format, pool) do
    attrs = %{
      "name" => format.name,
      "description" => format.description,
      "date" => Date.to_iso8601(format.date),
      "topics" => Enum.map(format.topics, &%{"name" => &1.name})
    }

    result =
      Repo.transaction(fn ->
        created =
          case Quiz.create_format(attrs) do
            {:ok, created} -> created
            {:error, changeset} -> Repo.rollback({:format, changeset})
          end

        counts =
          created.topics
          |> Enum.zip(format.topics)
          |> Enum.reduce(%{questions: 0, linked: 0, missing: 0, warnings: []}, fn {topic, data},
                                                                                  acc ->
            create_questions(topic, data, format.name, pool, acc)
          end)

        {created, counts}
      end)

    case result do
      {:ok, {created, counts}} ->
        counts = %{counts | warnings: Enum.reverse(counts.warnings)}
        {:ok, add_avatar_cards(created, format, pool, counts)}

      {:error, {:format, %Ecto.Changeset{} = cs}} ->
        if Enum.any?(Keyword.get_values(cs.errors, :name), fn {_, o} ->
             o[:constraint] == :unique
           end),
           do: {:skip},
           else: {:error, "format: " <> errors(cs)}

      {:error, {:question, where, %Ecto.Changeset{} = cs}} ->
        {:error, "#{where}: " <> errors(cs)}
    end
  end

  # After the transaction: a card that can't be a picture (not fetched, newer
  # than the format) costs a warning, not the format.
  defp add_avatar_cards(created, format, pool, counts) do
    {added, warnings} =
      Enum.reduce(format.avatars, {0, []}, fn card, {added, warnings} ->
        name = card.name || "card #{card.password}"

        result =
          case Map.get(pool, card.password) do
            {:ok, id, _name} ->
              case Quiz.add_avatar_card(created.id, id) do
                {:ok, _} -> {:ok, apply_crop(card, id, created.name, name)}
                {:error, reason} -> {:error, reason}
              end

            _missing ->
              {:error, :missing}
          end

        case result do
          {:ok, crop_warnings} ->
            {added + 1, warnings ++ crop_warnings}

          {:error, reason} ->
            {added, warnings ++ [avatar_warning(format.name, name, card.password, reason)]}
        end
      end)

    counts
    |> Map.put(:warnings, counts.warnings ++ warnings)
    |> Map.put(:avatars, added)
    |> Map.put(:avatars_missing, length(format.avatars) - added)
  end

  # A crop already stored for the card is kept: the local one wins, silently.
  defp apply_crop(%{crop: nil}, _id, _format, _name), do: []

  defp apply_crop(%{crop: :invalid, password: password}, _id, format, name),
    do: [
      "#{format}: the crop of avatar card #{name} (#{password}) is not valid and was ignored."
    ]

  defp apply_crop(%{crop: crop}, id, _format, _name) do
    unless Repo.get(MillenniumQuiz.Quiz.CardAvatarCrop, id), do: Quiz.set_avatar_crop(id, crop)

    []
  end

  defp avatar_warning(format, name, password, reason) do
    why =
      case reason do
        :missing -> "could not be fetched"
        :not_released -> "was not released by the format's date"
        :limit -> "is over the limit of #{Quiz.max_avatar_cards()}"
        _ -> "could not be added"
      end

    "#{format}: avatar card #{name} (#{password}) #{why} and is not a profile picture."
  end

  defp create_questions(topic, data, format_name, pool, acc) do
    data.questions
    |> Enum.with_index(1)
    |> Enum.reduce(acc, fn {q, i}, acc ->
      {entries, text, warnings, missing} = link_cards(q, pool, format_name, data.name, i)

      attrs = %{
        "text" => text,
        "submitted_by" => q.submitted_by,
        "choices" => q.choices
      }

      case Quiz.create_question(topic, attrs, entries) do
        {:ok, _} ->
          %{
            acc
            | questions: acc.questions + 1,
              linked: acc.linked + length(Enum.uniq_by(entries, &elem(&1, 0))),
              missing: acc.missing + missing,
              warnings: Enum.reverse(warnings, acc.warnings)
          }

        {:error, cs} ->
          Repo.rollback({:question, "topic \"#{data.name}\", question #{i}", cs})
      end
    end)
  end

  defp link_cards(q, pool, format_name, topic_name, i) do
    where = "#{format_name} / #{topic_name} / question #{i}"

    Enum.reduce(q.cards, {[], q.text, [], 0}, fn card, {entries, text, warnings, missing} ->
      case Map.get(pool, card.password) do
        {:ok, id, current} ->
          if card.name && not same_name?(card.name, current) do
            # renamed since the export: keep the inline link working
            warning =
              "#{where}: card #{card.name} (#{card.password}) is called #{current} now; " <>
                "the link in the text was changed to match."

            {entries ++ [{id, card.owner}], CardLinks.rename(text, card.name, current),
             warnings ++ [warning], missing}
          else
            {entries ++ [{id, card.owner}], text, warnings, missing}
          end

        _missing ->
          name = card.name || "card #{card.password}"

          warning =
            "#{where}: card #{name} (#{card.password}) could not be fetched and is not linked."

          text = if card.name, do: CardLinks.unlink(text, card.name), else: text
          {entries, text, warnings ++ [warning], missing + 1}
      end
    end)
  end

  defp same_name?(a, b), do: String.downcase(String.trim(a)) == String.downcase(String.trim(b))

  defp errors(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts
        |> Enum.find_value(key, fn {k, v} -> if to_string(k) == key, do: v end)
        |> to_string()
      end)
    end)
    |> flatten()
    |> Enum.join("; ")
  end

  defp flatten(errors, prefix \\ nil) do
    Enum.flat_map(errors, fn
      {field, msgs} when is_list(msgs) ->
        name = if prefix, do: "#{prefix}.#{field}", else: to_string(field)

        Enum.flat_map(msgs, fn
          msg when is_binary(msg) -> ["#{name} #{msg}"]
          %{} = nested -> flatten(nested, name)
        end)

      {field, %{} = nested} ->
        flatten(nested, if(prefix, do: "#{prefix}.#{field}", else: to_string(field)))
    end)
  end
end
