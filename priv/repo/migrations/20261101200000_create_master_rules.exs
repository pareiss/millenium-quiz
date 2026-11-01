defmodule MillenniumQuiz.Repo.Migrations.CreateMasterRules do
  use Ecto.Migration

  # The Master Rules and the start date of the overlay-unit (Xyz) feature,
  # editable in the admin (`MillenniumQuiz.Quiz.MasterRules`). Two tiny tables
  # (3 and 1 rows): one is a rule with the zones its board has, the other a
  # feature with a date of its own that belongs to no rule.
  #
  # Seeded here because production has no seeds step. The values are a frozen
  # copy of the built-in defaults of `Quiz.MasterRule` of 2026-11-01. The
  # inserts skip a row that exists, so running the migration again (or after
  # a restore) changes nothing. `starts_on` of the first rule is NULL: it
  # covers every earlier date.
  #
  # `down` drops the tables; the code falls back to the built-in defaults.

  def up do
    create table(:master_rules) do
      add :key, :string, null: false
      add :name, :string, null: false
      add :position, :integer, null: false
      add :starts_on, :date
      add :emz, :boolean, null: false, default: false
      add :pendulum_scales, :boolean, null: false, default: false
      timestamps(type: :utc_datetime)
    end

    create unique_index(:master_rules, [:key])

    create table(:master_rule_features) do
      add :key, :string, null: false
      add :starts_on, :date, null: false
      timestamps(type: :utc_datetime)
    end

    create unique_index(:master_rule_features, [:key])

    execute """
            INSERT INTO master_rules (key, name, position, starts_on, emz, pendulum_scales, inserted_at, updated_at)
            VALUES
              ('mr1_2', 'Master Rule 1/2', 1, NULL, false, false, now(), now()),
              ('mr3', 'Master Rule 3', 2, DATE '2014-01-01', false, true, now(), now()),
              ('mr4', 'Master Rule 4', 3, DATE '2017-04-01', true, true, now(), now())
            ON CONFLICT (key) DO NOTHING
            """,
            "SELECT 1"

    execute """
            INSERT INTO master_rule_features (key, starts_on, inserted_at, updated_at)
            VALUES ('xyz', DATE '2011-06-01', now(), now())
            ON CONFLICT (key) DO NOTHING
            """,
            "SELECT 1"
  end

  def down do
    drop table(:master_rule_features)
    drop table(:master_rules)
  end
end
