defmodule MillenniumQuiz.Quiz.MasterRule do
  @moduledoc """
  The Master Rule in force on a date, and what its board has.

  | key      | from            | Extra Monster Zones | Pendulum scales |
  |----------|-----------------|---------------------|-----------------|
  | `:mr1_2` | the beginning   | no                  | no              |
  | `:mr3`   | 2014-01-01      | no                  | yes             |
  | `:mr4`   | 2017-04-01      | yes                 | yes             |

  Pendulum scales: in Master Rule 3 the Pendulum Zones were separate zones.
  The board deliberately draws scales in the outer Spell/Trap Zones for every
  era so it stays small; this is intended (see `MillenniumQuiz.Quiz.Board`).

  Overlay units (Xyz materials) are not tied to a Master Rule: Xyz Monsters
  came out in the middle of the first era (TCG 2011-06), so `allows?/2` with a
  date answers `:overlay_units` from the `:xyz` feature date; with a bare rule
  key it is lenient and says yes. The Extra Deck itself exists in every era
  (Fusion Monsters); whether a Synchro, Xyz, Pendulum or Link Monster exists on
  a date is decided by its own release date, not here.

  The dates are from memory and may be wrong, so an admin can edit them
  (`MillenniumQuiz.Quiz.MasterRules`, page `/admin/master-rules`). `rules/0`
  and `features/0` are the only readers of that source and every other
  function reads them; the built-in values below (`default_rules/0`,
  `default_features/0`) are what the table is seeded with and what is used when
  it is empty or the database cannot be read.
  """

  @enforce_keys [:key, :name, :starts_on]
  defstruct [:key, :name, :starts_on, emz: false, pendulum_scales: false]

  @type key :: :mr1_2 | :mr3 | :mr4
  @type t :: %__MODULE__{
          key: key,
          name: String.t(),
          starts_on: Date.t() | nil,
          emz: boolean,
          pendulum_scales: boolean
        }

  # In order of starts_on; the first has no start (it covers every earlier date).
  @rules [
    %{key: :mr1_2, name: "Master Rule 1/2", starts_on: nil, emz: false, pendulum_scales: false},
    %{
      key: :mr3,
      name: "Master Rule 3",
      starts_on: ~D[2014-01-01],
      emz: false,
      pendulum_scales: true
    },
    %{
      key: :mr4,
      name: "Master Rule 4",
      starts_on: ~D[2017-04-01],
      emz: true,
      pendulum_scales: true
    }
  ]

  # Features with their own date, independent of the rule.
  @features [%{key: :xyz, starts_on: ~D[2011-06-01]}]

  @doc "The built-in rules as maps, oldest first (the seed and the fallback)."
  def default_rules, do: @rules

  @doc "The built-in features, as `[%{key, starts_on}]`."
  def default_features, do: @features

  @doc "All rules in force (the stored settings), oldest first."
  @spec rules() :: [t]
  def rules, do: elem(MillenniumQuiz.Quiz.MasterRules.current(), 0)

  @doc "Features with a start date of their own, as `[%{key, starts_on}]`."
  def features, do: elem(MillenniumQuiz.Quiz.MasterRules.current(), 1)

  @doc "The key of the rule in force on `date`; no date (a format without one) is the newest."
  @spec for_date(Date.t() | nil) :: key
  def for_date(nil), do: rules() |> List.last() |> Map.fetch!(:key)

  def for_date(%Date{} = date) do
    rules()
    |> Enum.filter(&(is_nil(&1.starts_on) or Date.compare(&1.starts_on, date) != :gt))
    |> List.last()
    |> Map.fetch!(:key)
  end

  @doc "The rule struct for a key, a date or nil."
  @spec get(key | Date.t() | nil) :: t
  def get(key) when is_atom(key) and not is_nil(key) do
    Enum.find(rules(), &(&1.key == key)) ||
      raise ArgumentError, "unknown Master Rule #{inspect(key)}"
  end

  def get(date), do: get(for_date(date))

  @doc """
  Whether a rule (a key, a date or nil) has `feature`: `:emz`,
  `:pendulum_scales` or `:overlay_units`.
  """
  @spec allows?(key | Date.t() | nil, :emz | :pendulum_scales | :overlay_units) :: boolean
  def allows?(rule, :emz), do: get(rule).emz
  def allows?(rule, :pendulum_scales), do: get(rule).pendulum_scales
  def allows?(%Date{} = date, :overlay_units), do: feature_on?(:xyz, date)
  def allows?(_key_or_nil, :overlay_units), do: true

  defp feature_on?(key, date) do
    case Enum.find(features(), &(&1.key == key)) do
      nil -> true
      %{starts_on: starts_on} -> Date.compare(starts_on, date) != :gt
    end
  end
end
