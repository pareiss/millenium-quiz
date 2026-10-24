defmodule MillenniumQuizWeb.CoreComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest
  import MillenniumQuizWeb.CoreComponents

  test "a table scrolls sideways inside its own wrapper, not the page" do
    assigns = %{rows: [%{name: "Ann"}]}

    html =
      rendered_to_string(~H"""
      <.table id="people" rows={@rows}>
        <:col :let={row} label="Name">{row.name}</:col>
      </.table>
      """)

    doc = LazyHTML.from_fragment(html)

    assert doc
           |> LazyHTML.query("div.overflow-x-auto > table > tbody#people")
           |> Enum.count() == 1
  end
end
