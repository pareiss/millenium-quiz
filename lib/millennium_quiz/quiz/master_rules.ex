defmodule MillenniumQuiz.Quiz.MasterRules do
  @moduledoc """
  The Master Rule settings an admin can edit: the start dates of Master Rule 3
  and 4 and the date overlay units (Xyz) exist. Stored in `master_rules` (one
  row per rule: start date and what its board has) and `master_rule_features`
  (one row per feature with a date of its own). The rows are seeded by the
  migration that creates them.

  `MillenniumQuiz.Quiz.MasterRule` reads `current/0`; nothing else holds dates.

  ## Cache

  `current/0` keeps what it read in `:persistent_term` (a handful of rows, read
  many times per game and per validation) and `save/1`, `reset/0` and `import/1`
  erase it, so the next read sees the new dates. The cache is per node, which
  is fine for one node (the app runs on one). It is switched off in the test
  suite (`config :millennium_quiz, MillenniumQuiz.Quiz.MasterRules, cache: false`)
  so a test cannot leak dates into another; the cache tests switch it on and
  clean up after themselves.

  ## Never crashes a game

  If the tables are empty, a row is missing, or the database cannot be read,
  the built-in defaults of `MasterRule` are used for what is missing. A read
  that failed is not cached.

  ## What editing changes

  Only the dates are editable; which zones a rule has is part of the rule.
  A saved question keeps its board; nothing is rewritten when a date changes.
  A board is checked against the dates in force whenever it is validated or
  resolved (`Quiz.Board`), so a board that no longer fits is refused then.
  Nothing warns an admin about such questions in advance.
  """
  import Ecto.Query

  alias MillenniumQuiz.Quiz.{MasterRule, MasterRuleFeature, MasterRuleSetting}
  alias MillenniumQuiz.Repo

  @cache_key {__MODULE__, :current}
  @generation_key {__MODULE__, :generation}

  # What "plausible" means for a date: the TCG began in March 2002; Xyz
  # Monsters are from 2008 (OCG) to 2011 (TCG).
  @earliest ~D[2002-03-08]
  @latest ~D[2035-12-31]
  @xyz_earliest ~D[2008-01-01]
  @xyz_latest ~D[2016-12-31]

  @type dates :: %{mr3: Date.t(), mr4: Date.t(), xyz: Date.t()}

  @doc "`{rules, features}` in force: rule structs (oldest first) and `[%{key, starts_on}]`."
  @spec current() :: {[MasterRule.t()], [%{key: atom, starts_on: Date.t()}]}
  def current do
    case cached() do
      {:ok, value} ->
        value

      :miss ->
        generation = generation()

        case load() do
          {:ok, value} ->
            # A save that finished while we were reading bumped the generation:
            # what we read may be the old dates, so it is used but not kept.
            if generation() == generation, do: put_cache(value)
            value

          :error ->
            defaults()
        end
    end
  end

  @doc "The built-in defaults, as `{rules, features}`."
  def defaults do
    {Enum.map(MasterRule.default_rules(), &struct!(MasterRule, &1)),
     MasterRule.default_features()}
  end

  @doc "The editable dates in force."
  @spec dates() :: dates
  def dates do
    {rules, features} = current()
    to_dates(rules, features)
  end

  @doc "The editable dates of the built-in defaults."
  @spec default_dates() :: dates
  def default_dates do
    {rules, features} = defaults()
    to_dates(rules, features)
  end

  defp to_dates(rules, features) do
    %{
      mr3: Enum.find(rules, &(&1.key == :mr3)).starts_on,
      mr4: Enum.find(rules, &(&1.key == :mr4)).starts_on,
      xyz: Enum.find(features, &(&1.key == :xyz)).starts_on
    }
  end

  ## Validation

  @doc """
  Validates edited dates, given as `%{"mr3" => "2014-01-01", "mr4" => ..., "xyz" => ...}`
  (strings, as a form sends them; `Date`s are fine too).

  Returns `{:ok, dates}` or `{:error, %{field => message}}` with the fields
  `:mr3`, `:mr4` and `:xyz`. The first rule has no start date and the rules
  are contiguous (each one ends where the next starts), so "no gaps and no
  overlaps" means the starts are in strict order: Master Rule 3 before Master
  Rule 4.
  """
  @spec validate(map) :: {:ok, dates} | {:error, %{atom => String.t()}}
  def validate(params) do
    parsed = %{
      mr3: parse(params, :mr3),
      mr4: parse(params, :mr4),
      xyz: parse(params, :xyz)
    }

    errors =
      Enum.reduce(parsed, %{}, fn
        {field, {:error, msg}}, acc -> Map.put(acc, field, msg)
        {field, {:ok, date}}, acc -> check_range(acc, field, date)
      end)

    errors =
      with {:ok, mr3} <- parsed.mr3,
           {:ok, mr4} <- parsed.mr4,
           true <- Date.compare(mr3, mr4) != :lt do
        Map.put_new(
          errors,
          :mr4,
          "must be after the start of Master Rule 3 (#{Date.to_iso8601(mr3)}): the rules follow each other without a gap or an overlap."
        )
      else
        _ -> errors
      end

    if errors == %{} do
      {:ok, %{mr3: ok(parsed.mr3), mr4: ok(parsed.mr4), xyz: ok(parsed.xyz)}}
    else
      {:error, errors}
    end
  end

  defp ok({:ok, v}), do: v

  defp parse(params, field) do
    value = Map.get(params, Atom.to_string(field)) || Map.get(params, field)

    case value do
      %Date{} = d ->
        {:ok, d}

      v when is_binary(v) ->
        case Date.from_iso8601(String.trim(v)) do
          {:ok, d} -> {:ok, d}
          _ -> {:error, "must be a date like 2014-01-01."}
        end

      _ ->
        {:error, "is required (a date like 2014-01-01)."}
    end
  end

  defp check_range(errors, :xyz, date) do
    if Date.compare(date, @xyz_earliest) == :lt or Date.compare(date, @xyz_latest) == :gt do
      Map.put(
        errors,
        :xyz,
        "is not plausible: Xyz Monsters came out between #{Date.to_iso8601(@xyz_earliest)} and #{Date.to_iso8601(@xyz_latest)}."
      )
    else
      errors
    end
  end

  defp check_range(errors, field, date) do
    if Date.compare(date, @earliest) == :lt or Date.compare(date, @latest) == :gt do
      Map.put(
        errors,
        field,
        "is not plausible: the TCG began on #{Date.to_iso8601(@earliest)}; pick a date up to #{Date.to_iso8601(@latest)}."
      )
    else
      errors
    end
  end

  ## Saving

  @doc "Validates and stores the dates; the cache is cleared. See `validate/1`."
  @spec save(map) :: {:ok, dates} | {:error, %{atom => String.t()}}
  def save(params) do
    with {:ok, dates} <- validate(params),
         :ok <- write(dates) do
      {:ok, dates}
    end
  end

  @doc "Puts the built-in default dates back."
  @spec reset() :: {:ok, dates} | {:error, %{atom => String.t()}}
  def reset do
    dates = default_dates()

    with :ok <- write(dates) do
      {:ok, dates}
    end
  end

  # Updates the rows, creating one that is missing from its default, in one
  # transaction. The cache is erased after it, whatever happened. A database
  # error is returned as `{:error, %{base: message}}`, never raised.
  defp write(dates) do
    {rules, _} = defaults()

    try do
      {:ok, _} =
        Repo.transaction(fn ->
          for {rule, i} <- Enum.with_index(rules, 1) do
            starts_on = if rule.key == :mr1_2, do: nil, else: Map.fetch!(dates, rule.key)

            Repo.insert!(
              %MasterRuleSetting{
                key: Atom.to_string(rule.key),
                name: rule.name,
                position: i,
                starts_on: starts_on,
                emz: rule.emz,
                pendulum_scales: rule.pendulum_scales
              },
              on_conflict: [set: [starts_on: starts_on, updated_at: now()]],
              conflict_target: :key
            )
          end

          Repo.insert!(
            %MasterRuleFeature{key: "xyz", starts_on: dates.xyz},
            on_conflict: [set: [starts_on: dates.xyz, updated_at: now()]],
            conflict_target: :key
          )
        end)

      :ok
    rescue
      e -> {:error, %{base: "could not be stored: #{Exception.message(e)}"}}
    after
      clear_cache()
    end
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)

  ## Backup

  @doc """
  The settings as a JSON-able map for the backup:
  `%{"rules" => [%{"key", "name", "starts_on", "emz", "pendulum_scales"}], "features" => [%{"key", "starts_on"}]}`.
  """
  def export do
    {rules, features} = current()

    %{
      "rules" =>
        Enum.map(rules, fn r ->
          %{
            "key" => Atom.to_string(r.key),
            "name" => r.name,
            "starts_on" => r.starts_on && Date.to_iso8601(r.starts_on),
            "emz" => r.emz,
            "pendulum_scales" => r.pendulum_scales
          }
        end),
      "features" =>
        Enum.map(
          features,
          &%{"key" => Atom.to_string(&1.key), "starts_on" => Date.to_iso8601(&1.starts_on)}
        )
    }
  end

  @doc """
  Applies a `"master_rules"` section of a backup. Only the dates are taken
  (`mr3`, `mr4`, `xyz`), validated like an admin save; the zones a rule has
  belong to the rule and are not read. Returns `{:ok, dates}` or
  `{:error, message}` and changes nothing when the section is invalid.
  """
  @spec import(term) :: {:ok, dates} | {:error, String.t()}
  def import(%{"rules" => rules, "features" => features})
      when is_list(rules) and is_list(features) do
    params = %{
      "mr3" => section_date(rules, "mr3"),
      "mr4" => section_date(rules, "mr4"),
      "xyz" => section_date(features, "xyz")
    }

    case save(params) do
      {:ok, dates} -> {:ok, dates}
      {:error, errors} -> {:error, describe(errors)}
    end
  end

  def import(_), do: {:error, "needs a list of \"rules\" and a list of \"features\"."}

  defp section_date(list, key) do
    Enum.find_value(list, fn
      %{"key" => ^key, "starts_on" => d} -> d
      _ -> nil
    end)
  end

  defp describe(errors) do
    labels = %{mr3: "Master Rule 3", mr4: "Master Rule 4", xyz: "Xyz"}

    errors
    |> Enum.sort()
    |> Enum.map_join(" ", fn
      {:base, msg} -> "The dates #{msg}"
      {field, msg} -> "#{labels[field]} start date #{msg}"
    end)
  end

  ## Cache and loading

  @doc "Forgets what was read, so the next read goes to the database."
  def clear_cache do
    :persistent_term.put(@generation_key, System.unique_integer([:monotonic]))
    :persistent_term.erase(@cache_key)
  end

  defp generation, do: :persistent_term.get(@generation_key, 0)

  defp cache?, do: Application.get_env(:millennium_quiz, __MODULE__, [])[:cache] != false

  defp cached do
    if cache?() do
      case :persistent_term.get(@cache_key, :miss) do
        :miss -> :miss
        value -> {:ok, value}
      end
    else
      :miss
    end
  end

  defp put_cache(value) do
    if cache?(), do: :persistent_term.put(@cache_key, value)
  end

  # Defaults fill what the database lacks. Returns :error (and caches nothing)
  # when the database cannot be read.
  defp load do
    rows = Repo.all(from r in MasterRuleSetting, order_by: [asc: r.position, asc: r.id])
    feats = Repo.all(MasterRuleFeature)
    {default_rules, default_features} = defaults()

    rules =
      Enum.map(default_rules, fn d ->
        case Enum.find(rows, &(&1.key == Atom.to_string(d.key))) do
          nil ->
            d

          r ->
            %{
              d
              | name: r.name,
                starts_on: if(d.key == :mr1_2, do: nil, else: r.starts_on || d.starts_on),
                emz: r.emz,
                pendulum_scales: r.pendulum_scales
            }
        end
      end)

    features =
      Enum.map(default_features, fn d ->
        case Enum.find(feats, &(&1.key == Atom.to_string(d.key))) do
          nil -> d
          f -> %{d | starts_on: f.starts_on}
        end
      end)

    {:ok, {rules, features}}
  rescue
    _ -> :error
  catch
    :exit, _ -> :error
  end
end
