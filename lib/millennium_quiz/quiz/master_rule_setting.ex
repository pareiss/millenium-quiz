defmodule MillenniumQuiz.Quiz.MasterRuleSetting do
  @moduledoc "A stored Master Rule (table `master_rules`); see `MillenniumQuiz.Quiz.MasterRules`."
  use Ecto.Schema

  schema "master_rules" do
    field :key, :string
    field :name, :string
    field :position, :integer
    field :starts_on, :date
    field :emz, :boolean, default: false
    field :pendulum_scales, :boolean, default: false
    timestamps(type: :utc_datetime)
  end
end
