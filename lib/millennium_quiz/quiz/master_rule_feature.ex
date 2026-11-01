defmodule MillenniumQuiz.Quiz.MasterRuleFeature do
  @moduledoc "A stored feature date (table `master_rule_features`); see `MillenniumQuiz.Quiz.MasterRules`."
  use Ecto.Schema

  schema "master_rule_features" do
    field :key, :string
    field :starts_on, :date
    timestamps(type: :utc_datetime)
  end
end
