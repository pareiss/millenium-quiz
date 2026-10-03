defmodule MillenniumQuizWeb.ConfirmDialogTest do
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest
  import MillenniumQuizWeb.CoreComponents

  defp dialog(assigns) do
    ~H"""
    <.confirm_dialog id="thing" title="Delete it?" on_cancel="cancel" cancel_id={@cancel_id}>
      <p>Gone for good.</p>
      <:actions>
        <button id={@cancel_id || "thing-cancel"} phx-click="cancel">Cancel</button>
        <button id="thing-confirm" phx-click="delete">Delete</button>
      </:actions>
    </.confirm_dialog>
    """
  end

  defp count(doc, selector), do: doc |> LazyHTML.query(selector) |> Enum.count()

  test "is a labelled dialog that cancels on Esc and on the backdrop" do
    html = render_component(&dialog/1, cancel_id: nil)
    doc = LazyHTML.from_fragment(html)

    assert count(doc, "#thing[role=dialog][aria-modal=true][aria-labelledby=thing-title]") == 1
    assert count(doc, "#thing[phx-window-keydown=cancel][phx-key=escape]") == 1
    assert LazyHTML.query(doc, "#thing-title") |> LazyHTML.text() == "Delete it?"
    # the backdrop and the cancel button both send the cancel event
    assert count(doc, "#thing [phx-click=cancel]") == 2
    # the cancel button gets the focus when the dialog appears
    assert html =~ "thing-cancel"
    assert [focus] = LazyHTML.attribute(LazyHTML.query(doc, "#thing"), "phx-mounted")
    assert focus =~ "#thing-cancel"
  end

  test "focuses a custom cancel button" do
    html = render_component(&dialog/1, cancel_id: "keep-playing")

    [focus] =
      html
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("#thing")
      |> LazyHTML.attribute("phx-mounted")

    assert focus =~ "#keep-playing"
  end
end
