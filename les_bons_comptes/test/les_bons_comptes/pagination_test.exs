defmodule LesBonsComptes.PaginationTest do
  use LesBonsComptes.DataCase, async: true

  alias LesBonsComptes.Accounts
  alias LesBonsComptes.Pagination

  describe "paginate/3 with enumerables" do
    test "handles empty lists cleanly" do
      result = Pagination.paginate([], 1, 10)

      assert result.entries == []
      assert result.page_number == 1
      assert result.page_size == 10
      assert result.total_entries == 0
      assert result.total_pages == 1
      assert result.start_index == 0
      assert result.end_index == 0
      refute result.has_prev
      refute result.has_next
    end

    test "paginates single page dataset correctly" do
      items = ["A", "B", "C", "D"]
      result = Pagination.paginate(items, 1, 10)

      assert result.entries == ["A", "B", "C", "D"]
      assert result.page_number == 1
      assert result.page_size == 10
      assert result.total_entries == 4
      assert result.total_pages == 1
      assert result.start_index == 1
      assert result.end_index == 4
      refute result.has_prev
      refute result.has_next
    end

    test "paginates multi-page dataset correctly across pages" do
      items = Enum.map(1..25, &"item_#{&1}")

      # Page 1
      page1 = Pagination.paginate(items, 1, 10)
      assert length(page1.entries) == 10
      assert hd(page1.entries) == "item_1"
      assert List.last(page1.entries) == "item_10"
      assert page1.page_number == 1
      assert page1.total_entries == 25
      assert page1.total_pages == 3
      assert page1.start_index == 1
      assert page1.end_index == 10
      refute page1.has_prev
      assert page1.has_next

      # Page 2
      page2 = Pagination.paginate(items, 2, 10)
      assert length(page2.entries) == 10
      assert hd(page2.entries) == "item_11"
      assert List.last(page2.entries) == "item_20"
      assert page2.page_number == 2
      assert page2.start_index == 11
      assert page2.end_index == 20
      assert page2.has_prev
      assert page2.has_next

      # Page 3 (partial page)
      page3 = Pagination.paginate(items, 3, 10)
      assert length(page3.entries) == 5
      assert hd(page3.entries) == "item_21"
      assert List.last(page3.entries) == "item_25"
      assert page3.page_number == 3
      assert page3.start_index == 21
      assert page3.end_index == 25
      assert page3.has_prev
      refute page3.has_next
    end

    test "clamps out-of-bounds page numbers to total_pages gracefully" do
      items = ["A", "B"]
      result = Pagination.paginate(items, 5, 2)

      assert result.entries == ["A", "B"]
      assert result.page_number == 1
      assert result.total_entries == 2
      assert result.total_pages == 1
      refute result.has_prev
      refute result.has_next
    end

    test "coerces binary and invalid page parameters into positive integers" do
      items = ["A", "B", "C"]

      result_string = Pagination.paginate(items, "2", "2")
      assert result_string.page_number == 2
      assert result_string.page_size == 2
      assert result_string.entries == ["C"]

      result_invalid = Pagination.paginate(items, -1, 0)
      assert result_invalid.page_number == 1
      assert result_invalid.page_size == 1
    end
  end

  describe "page_range/3" do
    test "returns full continuous range when total_pages <= 7" do
      assert Pagination.page_range(1, 5) == [1, 2, 3, 4, 5]
      assert Pagination.page_range(3, 5) == [1, 2, 3, 4, 5]
      assert Pagination.page_range(5, 5) == [1, 2, 3, 4, 5]
      assert Pagination.page_range(1, 1) == [1]
    end

    test "includes ellipsis near end when current page is close to start" do
      range = Pagination.page_range(2, 10)
      assert range == [1, 2, 3, 4, :ellipsis_right, 10]
    end

    test "includes ellipsis on both sides when current page is in the middle" do
      range = Pagination.page_range(5, 10)
      assert range == [1, :ellipsis_left, 3, 4, 5, 6, 7, :ellipsis_right, 10]
    end

    test "includes ellipsis near start when current page is close to end" do
      range = Pagination.page_range(9, 10)
      assert range == [1, :ellipsis_left, 7, 8, 9, 10]
    end
  end

  describe "paginate_query/4 with Ecto" do
    test "paginates database records accurately" do
      for i <- 1..5 do
        Accounts.create_user(%{
          name: "User Page #{i}",
          email: "user_page_#{i}_#{System.unique_integer([:positive])}@test.com",
          password: "password123"
        })
      end

      import Ecto.Query
      alias LesBonsComptes.Accounts.User
      base_query = from(u in User, where: like(u.email, "user_page_%"), order_by: [asc: u.id])

      page1 = Pagination.paginate_query(base_query, LesBonsComptes.Repo, 1, 2)
      assert length(page1.entries) == 2
      assert page1.total_entries == 5
      assert page1.total_pages == 3
      assert page1.start_index == 1
      assert page1.end_index == 2
      assert page1.has_next
      refute page1.has_prev

      page3 = Pagination.paginate_query(base_query, LesBonsComptes.Repo, 3, 2)
      assert length(page3.entries) == 1
      assert page3.start_index == 5
      assert page3.end_index == 5
      assert page3.has_prev
      refute page3.has_next
    end
  end
end
