defmodule MillenniumQuiz.Quiz.Board do
  @moduledoc """
  A static Yu-Gi-Oh! board attached to a question (`questions.board`).

  Two shapes exist.

  ## The stored board (board.v1)

  A map with string keys, as in the research schema `board.v1`, kept in a
  `jsonb` column. It is a validated map, not an embedded schema: it is written
  whole and read whole, never queried by field, and the card entries are
  open-ended (the research format has optional keys such as `equip`), so a
  tree of embedded schemas would only add boilerplate. `cast/1` is the
  validation and also normalises (atom keys become strings, missing optional
  zones are filled in).

      %{
        "v" => 1,
        "turn" => 1,                   # optional, integer >= 1
        "phase" => "main1",            # optional: draw standby main1 battle main2 end
        "turnPlayer" => 1,             # optional, 1 or 2
        "emz" => [card | nil, card | nil],       # optional, [nil, nil] if missing
        "players" => [player, player]  # player 1 and player 2
      }

  A player: `"lp"` (0..99999), `"monsters"` (exactly 5, left to right),
  `"spells"` (exactly 5), `"field"` (card or nil), `"pendulum"` (2 slots, left
  and right scale; default `[nil, nil]`), `"hand"`, `"grave"` (bottom to top),
  `"banished"`, `"extra"` (lists of cards; default `[]`) and `"deck"` (a count
  >= 0; default 0). Only `lp`, `monsters` and `spells` are required.

  A card: `"code"` (the Konami password, `cards.password`, required) and
  optionally `"pos"` (`"atk"`, `"def"`, `"set"`, plus `"up"` = face-up for
  Spells and Traps; monsters take `atk`/`def`/`set`), `"overlay"` (list of
  material passwords), `"counters"` (a count, or a list of
  `%{"type" => int, "count" => int}`), and the research keys `"atk"`, `"def"`
  (current values), `"up"`, `"equip"`, `"owner"`, `"by"`, `"mark"`.
  Unknown keys are an error.

  ## Pendulum scales (a deliberate simplification)

  The board draws the Pendulum scales in the outer Spell/Trap Zones
  (`spells[0]` and `spells[4]`) for every era. In Master Rule 3 the Pendulum
  Zones were separate zones; this is left out on purpose so the board stays
  small. A Master Rule 3 board with 5 Spells/Traps plus 2 scales is therefore
  not representable, and `validate/2` rejects a scale and a Spell/Trap in the
  same outer zone. This is intended, not a bug.

  ## The resolved board

  What the board component and the game snapshot use: string keys, cards
  loaded from the pool, JSON-encodable, never raising for a card that left the
  pool (it becomes the placeholder "Unknown card").

      %{
        "rule" => "mr1_2" | "mr3" | "mr4",
        "turn" => integer | nil,
        "phase" => "draw" | "standby" | "main1" | "battle" | "main2" | "end" | nil,
        "turn_player" => 1 | 2 | nil,
        "emz" => [card | nil, card | nil],
        "players" => [player, player]
      }

  player:

      %{"lp" => int, "monsters" => [card | nil] (5), "spells" => [card | nil] (5),
        "field" => card | nil, "hand" => [card], "grave" => [card],
        "banished" => [card], "extra" => [card], "deck" => int}

  card:

      %{"name" => s, "kind" => "normal" | "effect" | "fusion" | "ritual" | "synchro"
          | "xyz" | "link" | "pendulum" | "spell" | "trap",
        "atk" => int | nil, "def" => int | nil, "level" => int | nil,
        "pos" => "atk" | "def" | "set", "overlay" => int, "counters" => int,
        "art" => url | nil, "scale" => bool, "password" => int}

  `overlay` is the number of units, `counters` the total of all counter types.
  `pos` of a face-up Spell/Trap, of a card without one and of `"up"` is
  `"atk"`; `"set"` is face-down. A Pendulum scale is placed in `spells[0]`
  (left) and `spells[4]` (right) with `"scale" => true`; a scale wins over a
  Spell/Trap stored in the same slot (validation rejects that board anyway).
  `atk`/`def` are the stored current values, else the printed ones (nil for
  `?`, for Spells and Traps). `level` is the Level or Rank (nil for Link and
  non-monsters). `art` is the artwork URL of the stored picture (the same
  `/cards/:id/artwork` the question cards use, in `:art_width`) or nil.

  ## Validation for a format

  `cast/1` checks the shape only. `validate/2` also needs the format's date
  (see `MillenniumQuiz.Quiz.MasterRule`) and the card pool. Both return a list
  of issues, `%{kind, path, message, code}`: `kind` is `:shape`, `:missing`
  (a password not in the pool), `:not_released` or `:zone`; `path` says where
  ("player 1 monster zone 3"); `code` is the password for card issues.
  `missing_passwords/1` lists the passwords a later importer could fetch.

  Leniencies (not checked): which card type may stand in which zone, that
  Extra Deck cards are Extra Deck types, that a stored pendulum card is a
  Pendulum Monster, the number of cards in the hand or graveyard, the
  `equip` target, and a card on a Master Rule board that cannot stand there
  by its own text.
  """

  import Ecto.Query

  alias MillenniumQuiz.Cards.Card
  alias MillenniumQuiz.Quiz.MasterRule
  alias MillenniumQuiz.Repo

  @max_lp 99_999
  @phases ~w(draw standby main1 battle main2 end)
  @monster_pos ~w(atk def set)
  @other_pos ~w(up atk def set)
  @card_keys ~w(code pos up atk def overlay counters equip owner by mark)
  @list_zones ~w(hand grave banished extra)

  @type issue :: %{
          kind: :shape | :missing | :not_released | :zone,
          path: String.t(),
          message: String.t(),
          code: pos_integer | nil
        }

  def max_lp, do: @max_lp

  ## Shape

  @doc """
  Checks the shape of a stored board (a map, or a JSON string) and returns
  the normalised board.
  """
  @spec cast(term) :: {:ok, map} | {:error, [issue]}
  def cast(input) do
    with {:ok, map} <- decode(input) do
      cast_board(map)
    end
  end

  defp decode(%{} = map) when not is_struct(map), do: {:ok, stringify(map)}

  defp decode(json) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, %{} = map} -> {:ok, map}
      _ -> {:error, [shape("board", "is not a JSON object")]}
    end
  end

  defp decode(_), do: {:error, [shape("board", "must be an object")]}

  defp stringify(%{} = map) when not is_struct(map),
    do: Map.new(map, fn {k, v} -> {to_string(k), stringify(v)} end)

  defp stringify(list) when is_list(list), do: Enum.map(list, &stringify/1)
  defp stringify(other), do: other

  defp cast_board(map) do
    {emz, emz_errors} =
      case Map.get(map, "emz") do
        nil -> {[nil, nil], []}
        list -> cast_slots(list, 2, "extra monster zone", "board", @monster_pos)
      end

    {players, player_errors} = cast_players(Map.get(map, "players"))

    errors =
      unknown_keys(map, ~w(v turn phase turnPlayer emz players), "board") ++
        check(map, "v", "board v", &(&1 == 1), "must be 1") ++
        check(
          map,
          "turn",
          "board turn",
          &(is_nil(&1) or (is_integer(&1) and &1 >= 1)),
          "must be an integer of 1 or more"
        ) ++
        check(
          map,
          "phase",
          "board phase",
          &(is_nil(&1) or &1 in @phases),
          "must be one of #{Enum.join(@phases, ", ")}"
        ) ++
        check(
          map,
          "turnPlayer",
          "board turn player",
          &(is_nil(&1) or &1 in [1, 2]),
          "must be 1 or 2"
        ) ++
        emz_errors ++ player_errors

    if errors == [] do
      board =
        %{"v" => 1, "emz" => emz, "players" => players}
        |> put_unless_nil("turn", map["turn"])
        |> put_unless_nil("phase", map["phase"])
        |> put_unless_nil("turnPlayer", map["turnPlayer"])

      {:ok, board}
    else
      {:error, errors}
    end
  end

  defp put_unless_nil(map, _key, nil), do: map
  defp put_unless_nil(map, key, value), do: Map.put(map, key, value)

  # "v" is required; the others may be missing (check/5 sees nil).
  defp check(map, key, path, ok?, message) do
    if ok?.(Map.get(map, key)), do: [], else: [shape(path, message)]
  end

  defp unknown_keys(map, known, path) do
    for key <- Map.keys(map),
        key not in known,
        do: shape(path, "has an unknown key #{inspect(key)}")
  end

  defp cast_players([p1, p2]) do
    {cast1, errors1} = cast_player(p1, 1)
    {cast2, errors2} = cast_player(p2, 2)
    {[cast1, cast2], errors1 ++ errors2}
  end

  defp cast_players(_), do: {[], [shape("board players", "must be a list of exactly 2 players")]}

  defp cast_player(%{} = raw, n) do
    who = "player #{n}"

    {monsters, e1} = cast_slots(raw["monsters"], 5, "monster zone", who, @monster_pos)
    {spells, e2} = cast_slots(raw["spells"], 5, "spell/trap zone", who, @other_pos)
    {field, e3} = cast_optional_card(raw["field"], "#{who} field zone", @other_pos)

    {pendulum, e4} =
      case Map.get(raw, "pendulum") do
        nil -> {[nil, nil], []}
        list -> cast_slots(list, 2, "pendulum zone", who, @other_pos)
      end

    {lists, e5} =
      Enum.map_reduce(@list_zones, [], fn zone, errors ->
        {cards, errs} = cast_card_list(Map.get(raw, zone), zone, who)
        {{zone, cards}, errors ++ errs}
      end)

    errors =
      unknown_keys(raw, ~w(lp monsters spells field pendulum hand grave banished extra deck), who) ++
        check(
          raw,
          "lp",
          "#{who} lp",
          &(is_integer(&1) and &1 in 0..@max_lp),
          "must be a whole number from 0 to #{@max_lp}"
        ) ++
        check(
          raw,
          "deck",
          "#{who} deck",
          &(is_nil(&1) or (is_integer(&1) and &1 >= 0)),
          "must be a count of 0 or more"
        ) ++
        e1 ++ e2 ++ e3 ++ e4 ++ e5

    player =
      Map.merge(
        %{
          "lp" => raw["lp"],
          "monsters" => monsters,
          "spells" => spells,
          "field" => field,
          "pendulum" => pendulum,
          "deck" => raw["deck"] || 0
        },
        Map.new(lists)
      )

    {player, errors}
  end

  defp cast_player(_, n), do: {nil, [shape("player #{n}", "must be an object")]}

  # A list of exactly `size` slots, each nil or a card.
  defp cast_slots(list, size, label, who, poss) when is_list(list) and length(list) == size do
    {cards, errors} =
      list
      |> Enum.with_index(1)
      |> Enum.map(fn {raw, i} -> cast_optional_card(raw, slot_path(who, label, i), poss) end)
      |> Enum.unzip()

    {cards, List.flatten(errors)}
  end

  defp cast_slots(_, size, label, who, _poss),
    do:
      {[],
       [shape("#{who} #{label}s", "must have exactly #{size} slots (use null for an empty one)")]}

  defp slot_path("board", label, i), do: "#{label} #{i}"
  defp slot_path(who, label, i), do: "#{who} #{label} #{i}"

  defp cast_card_list(nil, _zone, _who), do: {[], []}

  defp cast_card_list(list, zone, who) when is_list(list) do
    label = zone_label(zone)

    {cards, errors} =
      list
      |> Enum.with_index(1)
      |> Enum.map(fn
        {nil, i} -> {nil, [shape("#{who} #{label} #{i}", "must be a card, not null")]}
        {raw, i} -> cast_card(raw, "#{who} #{label} #{i}", @other_pos)
      end)
      |> Enum.unzip()

    {cards, List.flatten(errors)}
  end

  defp cast_card_list(_, zone, who),
    do: {[], [shape("#{who} #{zone_label(zone)}", "must be a list of cards")]}

  defp zone_label("hand"), do: "hand card"
  defp zone_label("grave"), do: "graveyard card"
  defp zone_label("banished"), do: "banished card"
  defp zone_label("extra"), do: "extra deck card"

  defp cast_optional_card(nil, _path, _poss), do: {nil, []}
  defp cast_optional_card(raw, path, poss), do: cast_card(raw, path, poss)

  defp cast_card(%{} = raw, path, poss) do
    errors =
      unknown_keys(raw, @card_keys, path) ++
        if(Map.has_key?(raw, "code"), do: [], else: [shape(path, "has no code")]) ++
        Enum.flat_map(raw, fn {k, v} -> card_field(k, v, path, poss) end)

    {raw, errors}
  end

  defp cast_card(_, path, _),
    do: {nil, [shape(path, "must be a card object like {\"code\": 123, \"pos\": \"atk\"}")]}

  defp card_field("code", v, path, _),
    do:
      if(pos_int?(v),
        do: [],
        else: [shape(path, "code must be a positive whole number (the password)")]
      )

  defp card_field("pos", v, path, poss),
    do: if(v in poss, do: [], else: [shape(path, "pos must be one of #{Enum.join(poss, ", ")}")])

  defp card_field("up", v, path, _),
    do: if(v == true, do: [], else: [shape(path, "up must be true")])

  defp card_field(k, v, path, _) when k in ["atk", "def"],
    do:
      if(is_integer(v) and v >= 0,
        do: [],
        else: [shape(path, "#{k} must be a whole number of 0 or more")]
      )

  defp card_field("owner", v, path, _),
    do: if(v in [1, 2], do: [], else: [shape(path, "owner must be 1 or 2")])

  defp card_field("by", v, path, _),
    do: if(v in [1, 2], do: [], else: [shape(path, "by must be 1 or 2")])

  defp card_field("mark", v, path, _),
    do:
      if(is_binary(v) and String.length(v) <= 3,
        do: [],
        else: [shape(path, "mark must be text of at most 3 characters")]
      )

  defp card_field("overlay", v, path, _) do
    if is_list(v) and Enum.all?(v, &pos_int?/1),
      do: [],
      else: [shape(path, "overlay must be a list of passwords")]
  end

  defp card_field("counters", v, path, _) do
    if pos_int?(v) or (is_list(v) and Enum.all?(v, &counter?/1)),
      do: [],
      else: [shape(path, "counters must be a count or a list of {\"type\": n, \"count\": n}")]
  end

  defp card_field("equip", v, path, _) do
    if match?(%{"p" => p, "m" => m} when p in [1, 2] and is_integer(m) and m in 0..6, v) and
         map_size(v) == 2,
       do: [],
       else: [shape(path, "equip must be {\"p\": 1 or 2, \"m\": 0..6}")]
  end

  defp card_field(_unknown, _, _, _), do: []

  defp counter?(%{"type" => t, "count" => c} = m),
    do: is_integer(t) and pos_int?(c) and map_size(m) == 2

  defp counter?(_), do: false

  defp pos_int?(v), do: is_integer(v) and v >= 1

  defp shape(path, message), do: %{kind: :shape, path: path, message: message, code: nil}

  ## Validation for a format

  @doc """
  Checks a cast board against the card pool and the Master Rule and release
  dates of a format. `date_or_rule` is the format's date (cards are checked
  against it too), a Master Rule key (no release check) or nil (a format
  without a date: newest rule, no release check).

  Returns `:ok` or `{:error, issues}` (see the moduledoc).
  """
  @spec validate(map, Date.t() | MasterRule.key() | nil) :: :ok | {:error, [issue]}
  def validate(board, date_or_rule) do
    entries = entries(board)
    pool = pool(entries |> Enum.flat_map(&codes/1) |> Enum.uniq())
    rule = MasterRule.get(date_or_rule)
    date = if match?(%Date{}, date_or_rule), do: date_or_rule

    errors =
      Enum.flat_map(entries, &entry_issues(&1, pool, date, rule, date_or_rule)) ++
        scale_conflicts(board)

    if errors == [], do: :ok, else: {:error, errors}
  end

  @doc "The passwords of `:missing` issues, to be fetched by an importer."
  @spec missing_passwords([issue]) :: [pos_integer]
  def missing_passwords(issues),
    do: issues |> Enum.filter(&(&1.kind == :missing)) |> Enum.map(& &1.code) |> Enum.uniq()

  @doc "Every password a board uses, including overlay units."
  @spec passwords(map) :: [pos_integer]
  def passwords(board), do: board |> entries() |> Enum.flat_map(&codes/1) |> Enum.uniq()

  defp codes(%{card: card}), do: [card["code"] | Map.get(card, "overlay", [])]

  defp entry_issues(%{card: card, zone: zone, path: path}, pool, date, rule, date_or_rule) do
    overlay = Map.get(card, "overlay", [])

    zone_issues =
      zone_issue(zone, path, rule, date_or_rule) ++
        overlay_issues(overlay, zone, path, date_or_rule, Map.get(pool, card["code"]))

    card_issues =
      [
        {card["code"], path}
        | Enum.map(Enum.with_index(overlay, 1), fn {c, i} -> {c, "#{path} overlay unit #{i}"} end)
      ]
      |> Enum.flat_map(fn {code, where} -> pool_issue(code, where, pool, date) end)

    card_issues ++ zone_issues
  end

  defp pool_issue(code, path, pool, date) do
    case Map.get(pool, code) do
      nil ->
        [
          %{
            kind: :missing,
            path: path,
            code: code,
            message: "card #{code} is not in the card pool"
          }
        ]

      %{tcg_release_date: released} = row when not is_nil(released) and not is_nil(date) ->
        if Date.compare(released, date) == :gt,
          do: [
            %{
              kind: :not_released,
              path: path,
              code: code,
              message:
                "#{row.name} (#{code}) was released on #{released}, after the format's date #{date}"
            }
          ],
          else: []

      _ ->
        []
    end
  end

  defp zone_issue(:emz, path, rule, _) do
    if rule.emz,
      do: [],
      else: [zone(path, "the Extra Monster Zones do not exist under #{rule.name}")]
  end

  defp zone_issue(:pendulum, path, rule, _) do
    if rule.pendulum_scales,
      do: [],
      else: [zone(path, "Pendulum Zones (scales) do not exist under #{rule.name}")]
  end

  defp zone_issue(_, _, _, _), do: []

  defp overlay_issues([], _zone, _path, _rule, _row), do: []

  defp overlay_issues(_overlay, zone, path, date_or_rule, row) do
    cond do
      zone not in [:monsters, :emz] ->
        [zone(path, "only a monster on the field can have overlay units")]

      not MasterRule.allows?(date_or_rule, :overlay_units) ->
        [zone(path, "overlay units (Xyz Monsters) did not exist on the format's date")]

      row && row.frame_type && not String.starts_with?(row.frame_type, "xyz") ->
        [zone(path, "#{row.name} is not an Xyz Monster, so it cannot have overlay units")]

      true ->
        []
    end
  end

  # A scale takes the place of the outer Spell/Trap Zone: spells[0] and spells[4].
  # DECIDED ON PURPOSE (PR #69, F1): in Master Rule 3 the Pendulum Zones were
  # separate zones, but the board draws the scales in the outer Spell/Trap Zones
  # for every era so the board stays small. Consequence: an MR3 board with 5
  # Spell/Traps plus 2 scales cannot be represented, so a scale and a Spell/Trap
  # in the same outer zone is rejected for every rule that has scales.
  defp scale_conflicts(%{"players" => players}) do
    for {%{"pendulum" => pendulum, "spells" => spells}, n} <- Enum.with_index(players, 1),
        {scale, slot, side} <- [
          {Enum.at(pendulum, 0), 0, "left"},
          {Enum.at(pendulum, 1), 4, "right"}
        ],
        scale != nil,
        Enum.at(spells, slot) != nil do
      zone(
        "player #{n} spell/trap zone #{slot + 1}",
        "the #{side} Pendulum scale is drawn in this outer Spell/Trap Zone (the board has no separate Pendulum Zones, in any Master Rule), so a scale and a Spell/Trap cannot both be there"
      )
    end
  end

  defp zone(path, message), do: %{kind: :zone, path: path, message: message, code: nil}

  defp pool([]), do: %{}

  defp pool(codes) do
    Repo.all(
      from c in Card,
        where: c.password in ^codes,
        select:
          map(c, [
            :id,
            :password,
            :name,
            :tcg_release_date,
            :frame_type,
            :kind,
            :card_type,
            :monster_type_line,
            :level,
            :rank,
            :atk,
            :def,
            :pendulum_scale
          ])
    )
    |> Map.new(&{&1.password, &1})
  end

  # Every card of the board with where it is.
  defp entries(%{} = board) do
    emz =
      for {card, i} <- Enum.with_index(Map.get(board, "emz") || [], 1),
          card != nil,
          do: %{zone: :emz, path: "extra monster zone #{i}", card: card}

    players =
      for {player, n} <- Enum.with_index(Map.get(board, "players") || [], 1),
          entry <- player_entries(player || %{}, "player #{n}"),
          do: entry

    emz ++ players
  end

  defp player_entries(player, who) do
    slots =
      for {zone, label} <- [
            monsters: "monster zone",
            spells: "spell/trap zone",
            pendulum: "pendulum zone"
          ],
          {card, i} <- Enum.with_index(Map.get(player, Atom.to_string(zone)) || [], 1),
          card != nil,
          do: %{zone: zone, path: "#{who} #{label} #{i}", card: card}

    field =
      case player["field"] do
        nil -> []
        card -> [%{zone: :field, path: "#{who} field zone", card: card}]
      end

    lists =
      for {zone, label} <- [
            hand: "hand card",
            grave: "graveyard card",
            banished: "banished card",
            extra: "extra deck card"
          ],
          {card, i} <- Enum.with_index(Map.get(player, Atom.to_string(zone)) || [], 1),
          do: %{zone: zone, path: "#{who} #{label} #{i}", card: card}

    slots ++ field ++ lists
  end

  ## Resolving

  @doc """
  Turns a stored board into the resolved board (see the moduledoc) with one
  query for all cards. `rule` is a Master Rule key or a format date.

  Options: `:art_width` (200 or 400, default 200) for the artwork URLs; `nil`
  for the original.
  """
  @spec resolve(map | nil, MasterRule.key() | Date.t() | nil, keyword) :: map | nil
  def resolve(board, rule, opts \\ [])
  def resolve(nil, _rule, _opts), do: nil

  def resolve(%{} = board, rule, opts) do
    board = stringify(board)
    key = MasterRule.get(rule).key
    width = Keyword.get(opts, :art_width, 200)
    pool = resolve_pool(passwords(board))
    ctx = %{pool: pool, width: width}

    players =
      board["players"]
      |> List.wrap()
      |> Enum.map(&resolve_player(&1, ctx))

    %{
      "rule" => Atom.to_string(key),
      "turn" => board["turn"],
      "phase" => board["phase"],
      "turn_player" => board["turnPlayer"],
      "emz" => board |> Map.get("emz") |> pad(2) |> Enum.map(&resolve_card(&1, :emz, ctx)),
      "players" => players
    }
  end

  defp resolve_pool([]), do: %{}

  defp resolve_pool(codes) do
    Repo.all(
      from c in Card,
        left_join: a in assoc(c, :artwork),
        where: c.password in ^codes,
        select: {
          map(c, [
            :id,
            :password,
            :name,
            :frame_type,
            :kind,
            :card_type,
            :monster_type_line,
            :level,
            :rank,
            :atk,
            :def,
            :pendulum_scale
          ]),
          not is_nil(a.id)
        }
    )
    |> Map.new(fn {row, art?} -> {row.password, Map.put(row, :art?, art?)} end)
  end

  defp resolve_player(player, ctx) do
    player = player || %{}
    [left, right] = player |> Map.get("pendulum") |> pad(2)

    spells =
      player
      |> Map.get("spells")
      |> pad(5)
      |> Enum.map(&resolve_card(&1, :spells, ctx))
      # Scales go into the outer Spell/Trap Zones for every era (deliberate, see
      # scale_conflicts/1 and the Board moduledoc).
      |> place_scale(0, left, ctx)
      |> place_scale(4, right, ctx)

    %{
      "lp" => player["lp"] || 0,
      "monsters" =>
        player |> Map.get("monsters") |> pad(5) |> Enum.map(&resolve_card(&1, :monsters, ctx)),
      "spells" => spells,
      "field" => resolve_card(player["field"], :field, ctx),
      "hand" => cards(player["hand"], :hand, ctx),
      "grave" => cards(player["grave"], :grave, ctx),
      "banished" => cards(player["banished"], :banished, ctx),
      "extra" => cards(player["extra"], :extra, ctx),
      "deck" => player["deck"] || 0
    }
  end

  defp place_scale(spells, _slot, nil, _ctx), do: spells

  defp place_scale(spells, slot, raw, ctx),
    do:
      List.replace_at(spells, slot, raw |> resolve_card(:pendulum, ctx) |> Map.put("scale", true))

  defp cards(nil, _zone, _ctx), do: []

  defp cards(list, zone, ctx),
    do: list |> Enum.reject(&is_nil/1) |> Enum.map(&resolve_card(&1, zone, ctx))

  defp pad(list, n), do: ((list || []) ++ List.duplicate(nil, n)) |> Enum.take(n)

  defp resolve_card(nil, _zone, _ctx), do: nil

  defp resolve_card(%{"code" => code} = raw, zone, %{pool: pool, width: width}) do
    row = Map.get(pool, code)

    base =
      case row do
        nil -> placeholder(zone)
        row -> printed(row, width)
      end

    base
    |> Map.merge(%{
      "pos" => pos(raw["pos"]),
      "overlay" => length(raw["overlay"] || []),
      "counters" => counters(raw["counters"]),
      "scale" => false,
      "password" => code
    })
    |> override(raw, "atk")
    |> override(raw, "def")
  end

  defp resolve_card(_, _zone, _ctx), do: nil

  defp override(card, raw, key) do
    if is_integer(raw[key]), do: Map.put(card, key, raw[key]), else: card
  end

  defp placeholder(zone) do
    %{
      "name" => "Unknown card",
      "kind" => if(zone in [:spells, :field, :pendulum], do: "spell", else: "normal"),
      "atk" => nil,
      "def" => nil,
      "level" => nil,
      "art" => nil
    }
  end

  defp printed(row, width) do
    kind = kind(row)
    monster? = kind not in ["spell", "trap"]

    %{
      "name" => row.name,
      "kind" => kind,
      "atk" => if(monster?, do: stat(row.atk)),
      "def" => if(monster? and kind != "link", do: stat(row.def)),
      "level" => if(monster? and kind != "link", do: row.level || row.rank),
      "art" => if(row.art?, do: art_url(row.id, width))
    }
  end

  defp art_url(id, nil), do: "/cards/#{id}/artwork"
  defp art_url(id, width), do: "/cards/#{id}/artwork?w=#{width}"

  defp stat(nil), do: nil

  defp stat(text) do
    case Integer.parse(text) do
      {n, ""} -> n
      _ -> nil
    end
  end

  defp pos(pos) when pos in ["def", "set"], do: pos
  defp pos(_), do: "atk"

  defp counters(nil), do: 0
  defp counters(n) when is_integer(n), do: n
  defp counters(list) when is_list(list), do: list |> Enum.map(&(&1["count"] || 0)) |> Enum.sum()
  defp counters(_), do: 0

  @frames ~w(normal effect ritual fusion synchro xyz link spell trap)

  defp kind(row) do
    frame = row.frame_type || ""

    cond do
      String.ends_with?(frame, "_pendulum") or is_integer(row.pendulum_scale) -> "pendulum"
      frame in @frames -> frame
      frame == "token" -> "normal"
      row.kind in ["Spell", "Trap"] -> String.downcase(row.kind)
      true -> kind_from_text("#{row.monster_type_line} / #{row.card_type}")
    end
  end

  # Whole segments of a type line such as "Spellcaster / Normal", never
  # substrings: "Spellcaster" is a monster type, not a Spell.
  defp kind_from_text(text) do
    segments =
      text |> String.downcase() |> String.split("/") |> Enum.map(&String.trim/1)

    Enum.find_value(
      ~w(spell trap fusion synchro xyz link ritual pendulum normal),
      "effect",
      &(&1 in segments && &1)
    )
  end
end
