defmodule LesBonsComptes.Pagination do
  @moduledoc """
  Unified pagination data structure and utility functions across all application levels.

  Supports both:
  - In-memory list pagination (`paginate/3`)
  - Database Ecto query pagination (`paginate_query/4`)
  """

  import Ecto.Query, only: [exclude: 2, limit: 2, offset: 2, select: 3]

  defstruct [
    :entries,
    :page_number,
    :page_size,
    :total_entries,
    :total_pages,
    :has_prev,
    :has_next,
    :start_index,
    :end_index
  ]

  @type t :: %__MODULE__{
          entries: list(),
          page_number: pos_integer(),
          page_size: pos_integer(),
          total_entries: non_neg_integer(),
          total_pages: non_neg_integer(),
          has_prev: boolean(),
          has_next: boolean(),
          start_index: non_neg_integer(),
          end_index: non_neg_integer()
        }

  @doc """
  Paginates an in-memory list or enumerable.
  Accepts page and page_size as either integer or string (from URL query parameters).

  Returns a `%LesBonsComptes.Pagination{}` struct.
  """
  def paginate(list, page, page_size \\ 8) when is_list(list) do
    page_size = max(to_int(page_size, 8), 1)
    total_entries = length(list)
    total_pages = max(ceil(total_entries / page_size), 1)

    page_number =
      page
      |> to_int(1)
      |> max(1)
      |> min(total_pages)

    offset = (page_number - 1) * page_size
    entries = list |> Enum.drop(offset) |> Enum.take(page_size)

    start_index = if total_entries == 0, do: 0, else: offset + 1
    end_index = min(offset + page_size, total_entries)

    %__MODULE__{
      entries: entries,
      page_number: page_number,
      page_size: page_size,
      total_entries: total_entries,
      total_pages: total_pages,
      has_prev: page_number > 1,
      has_next: page_number < total_pages,
      start_index: start_index,
      end_index: end_index
    }
  end

  @doc """
  Paginates an Ecto.Query with database-level LIMIT, OFFSET and total count.
  """
  def paginate_query(query, repo, page, page_size \\ 8) do
    page_size = max(to_int(page_size, 8), 1)

    total_entries =
      query
      |> exclude(:order_by)
      |> exclude(:preload)
      |> select([q], count(q.id, :distinct))
      |> repo.one() || 0

    total_pages = max(ceil(total_entries / page_size), 1)

    page_number =
      page
      |> to_int(1)
      |> max(1)
      |> min(total_pages)

    offset = (page_number - 1) * page_size

    entries =
      query
      |> limit(^page_size)
      |> offset(^offset)
      |> repo.all()

    start_index = if total_entries == 0, do: 0, else: offset + 1
    end_index = min(offset + page_size, total_entries)

    %__MODULE__{
      entries: entries,
      page_number: page_number,
      page_size: page_size,
      total_entries: total_entries,
      total_pages: total_pages,
      has_prev: page_number > 1,
      has_next: page_number < total_pages,
      start_index: start_index,
      end_index: end_index
    }
  end

  @doc """
  Helper to generate page number ranges for display, including ellipsis logic
  when there are many pages (e.g. 1 2 3 ... 10).
  """
  def page_range(current_page, total_pages, window \\ 2) do
    cond do
      total_pages <= 7 ->
        Enum.to_list(1..total_pages)

      true ->
        left = max(1, current_page - window)
        right = min(total_pages, current_page + window)

        pages =
          Enum.uniq(
            [1] ++
              (if left > 2, do: [:ellipsis_left], else: []) ++
              Enum.to_list(left..right) ++
              (if right < total_pages - 1, do: [:ellipsis_right], else: []) ++
              [total_pages]
          )

        pages
    end
  end

  defp to_int(val, _default) when is_integer(val), do: val

  defp to_int(val, default) when is_binary(val) do
    case Integer.parse(val) do
      {num, _} -> num
      :error -> default
    end
  end

  defp to_int(_, default), do: default
end
