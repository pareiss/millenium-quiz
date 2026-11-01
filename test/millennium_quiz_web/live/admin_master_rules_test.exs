defmodule MillenniumQuizWeb.AdminMasterRulesTest do
  use MillenniumQuizWeb.ConnCase

  import Phoenix.LiveViewTest

  alias MillenniumQuiz.Quiz.{MasterRule, MasterRules}

  test "the page requires login", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/admin/login"}}} = live(conn, ~p"/admin/master-rules")
  end

  describe "logged in" do
    setup :register_and_log_in_user

    test "lists the rules with their dates and what they have", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/admin/master-rules")

      assert html =~ "Master Rule 1/2"
      assert html =~ "Master Rule 3"
      assert html =~ "Master Rule 4"
      assert has_element?(view, "#rules_mr3[value='2014-01-01']")
      assert has_element?(view, "#rules_mr4[value='2017-04-01']")
      assert has_element?(view, "#rules_xyz[value='2011-06-01']")
      refute has_element?(view, "#rules_mr1_2")
      assert has_element?(view, "#rule-mr1_2-has", "Extra Monster Zones: no")
      assert has_element?(view, "#rule-mr3-has", "Pendulum scales: yes")
      assert has_element?(view, "#rule-mr4-has", "Extra Monster Zones: yes")
      assert has_element?(view, "#master-rules-note", "keeps its board")
      assert has_element?(view, "#master-rules-note", "Nothing warns")
    end

    test "is in the admin menu, in the bar and in the folded menu", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/admin/master-rules")
      assert has_element?(view, "#site-header a[href='/admin/master-rules']", "Master Rules")
      assert has_element?(view, "#menu-master-rules")
    end

    test "saves new dates", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/admin/master-rules")

      html =
        view
        |> form("#master-rules-form",
          rules: %{"mr3" => "2013-06-01", "mr4" => "2017-06-01", "xyz" => "2012-01-01"}
        )
        |> render_submit()

      assert html =~ "Master Rules saved."

      assert MasterRules.dates() == %{
               mr3: ~D[2013-06-01],
               mr4: ~D[2017-06-01],
               xyz: ~D[2012-01-01]
             }

      assert MasterRule.for_date(~D[2013-06-01]) == :mr3
      assert has_element?(view, "#rules_mr3[value='2013-06-01']")
    end

    test "dates out of order are refused with a message, nothing is saved", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/admin/master-rules")

      html =
        view
        |> form("#master-rules-form",
          rules: %{"mr3" => "2018-01-01", "mr4" => "2017-04-01", "xyz" => "2011-06-01"}
        )
        |> render_submit()

      assert html =~ "must be after the start of Master Rule 3 (2018-01-01)"
      refute html =~ "Master Rules saved."
      assert MasterRules.dates() == MasterRules.default_dates()
      # what was typed stays
      assert has_element?(view, "#rules_mr3[value='2018-01-01']")
    end

    test "an implausible Xyz date and an empty date are refused", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/admin/master-rules")

      html =
        view
        |> form("#master-rules-form",
          rules: %{"mr3" => "", "mr4" => "2017-04-01", "xyz" => "2003-01-01"}
        )
        |> render_submit()

      assert html =~ "is not plausible: Xyz Monsters came out"
      assert html =~ "must be a date like 2014-01-01."
      assert MasterRules.dates() == MasterRules.default_dates()
    end

    test "errors show while typing", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/admin/master-rules")

      html =
        view
        |> form("#master-rules-form",
          rules: %{"mr3" => "2018-01-01", "mr4" => "2017-04-01", "xyz" => "2011-06-01"}
        )
        |> render_change()

      assert html =~ "must be after the start of Master Rule 3"
    end

    test "reset to defaults asks first, then restores", %{conn: conn} do
      {:ok, _} =
        MasterRules.save(%{"mr3" => "2013-06-01", "mr4" => "2017-06-01", "xyz" => "2012-01-01"})

      {:ok, view, _} = live(conn, ~p"/admin/master-rules")
      refute has_element?(view, "#reset-dialog")

      view |> element("#reset-master-rules") |> render_click()
      assert has_element?(view, "#reset-dialog", "2014-01-01")
      # nothing changed yet
      assert MasterRules.dates().mr3 == ~D[2013-06-01]

      view |> element("#reset-dialog-cancel") |> render_click()
      refute has_element?(view, "#reset-dialog")
      assert MasterRules.dates().mr3 == ~D[2013-06-01]

      view |> element("#reset-master-rules") |> render_click()
      html = view |> element("#reset-dialog-confirm") |> render_click()

      assert html =~ "reset to the defaults"
      assert MasterRules.dates() == MasterRules.default_dates()
      assert has_element?(view, "#rules_mr3[value='2014-01-01']")
    end
  end
end
