defmodule Editor.Block do
  @moduledoc """
  Represents a mid-tier element of a page. Contains multiple cells and is usually
  a self-contained section. For example, a title, a paragraph or a list.
  """
  defstruct id: nil, type: nil, cells: []

  @type id :: Editor.Utils.id()
  @type t :: %__MODULE__{}

  @spec new(String.t()) :: t
  def new(type \\ "p")

  def new(type) do
    %__MODULE__{
      cells: [Editor.Cell.new()],
      id: Editor.Utils.new_id(),
      type: type
    }
  end

  @doc """
  Updates content of specified cell in specified block with the new value.
  """
  @spec update(t, id, String.t()) :: t
  def update(%__MODULE__{cells: cells} = block, cell_id, value) do
    cell_index = Enum.find_index(cells, &(&1.id === cell_id))
    new_cells = List.update_at(cells, cell_index, &%{&1 | content: value})
    %{block | cells: new_cells}
  end

  @doc """
  If the first cell of the specified block contains markdown-like wildcard strings, transforms
  the block to a new type.

  ## Transforms

  - `#` becomes an `"h1"`
  - `##` becomes an `"h2"`
  - `###` becomes an `"h3"`
  - ````` becomes a `"pre"`
  - `* ` becomes an `"ul"`

  """
  @spec resolve_transform(t) :: t
  def resolve_transform(%__MODULE__{cells: [%{content: "# " <> _} | _]} = block) do
    transform(block, "h1")
  end

  def resolve_transform(%__MODULE__{cells: [%{content: "#&nbsp;" <> _} | _]} = block) do
    transform(block, "h1")
  end

  def resolve_transform(%__MODULE__{cells: [%{content: "## " <> _} | _]} = block) do
    transform(block, "h2")
  end

  def resolve_transform(%__MODULE__{cells: [%{content: "##&nbsp;" <> _} | _]} = block) do
    transform(block, "h2")
  end

  def resolve_transform(%__MODULE__{cells: [%{content: "### " <> _} | _]} = block) do
    transform(block, "h3")
  end

  def resolve_transform(%__MODULE__{cells: [%{content: "###&nbsp;" <> _} | _]} = block) do
    transform(block, "h3")
  end

  def resolve_transform(%__MODULE__{cells: [%{content: "```" <> _} | _]} = block) do
    transform(block, "pre")
  end

  def resolve_transform(%__MODULE__{cells: [%{content: "* " <> _} | _]} = block) do
    transform(block, "ul")
  end

  def resolve_transform(%__MODULE__{cells: [%{content: "*&nbsp;" <> _} | _]} = block) do
    transform(block, "ul")
  end

  def resolve_transform(%__MODULE__{} = block), do: block

  @spec transform(t, String.t()) :: t
  defp transform(%__MODULE__{cells: [cell | rest]} = block, "ul") do
    cells = Enum.map([Editor.Cell.trim(cell) | rest], &Editor.Cell.transform(&1, "li"))
    %{block | type: "ul", cells: cells}
  end

  defp transform(%__MODULE__{cells: [cell | rest]} = block, type) do
    cells = [Editor.Cell.trim(cell) | rest]
    %{block | type: type, cells: cells}
  end

  @doc """
  Peforms a backspace operation on a block.

  The backspace operation has a different outcome depending on the block type and cursor position.

  A "p" block, backspaced from the 0th cell gets removed

  Any other block backspaced from the 0th cell get's downgraded

    - "h1" to "h2"
    - "h2" to "h3"
    - any other block to "p"

    Backspace from a non-0th cell will perform the backspace operation on the cell itself, which
  can result in one of

  - deletion of the cell
  - join of the cell with the previous cell

  """
  @spec backspace(t, id) :: [] | [t]
  def backspace(%__MODULE__{cells: cells, type: type} = block, cell_id) do
    cell_index = Enum.find_index(cells, &(&1.id === cell_id))

    cond do
      cell_index === 0 and type === "p" ->
        []

      cell_index === 0 ->
        [block |> downgrade() |> downgrade_cells()]

      cell_index > 0 ->
        action = cells |> Enum.at(cell_index) |> Editor.Cell.backspace()

        new_cells =
          case action do
            :delete -> List.delete_at(cells, cell_index)
            :join_to_previous -> join_cells(block, cell_index, cell_index - 1)
          end

        [%{block | cells: new_cells}]
    end
  end

  @spec join_cells(t, integer, integer) :: list(Editor.Cell.t())
  defp join_cells(%__MODULE__{cells: cells}, from_index, to_index)
       when from_index < 0 or to_index < 0 do
    cells
  end

  defp join_cells(%__MODULE__{cells: cells}, from_index, to_index) do
    from_cell = Enum.at(cells, from_index)
    to_cell = Enum.at(cells, to_index)
    cell = Editor.Cell.join(to_cell, from_cell)

    cells
    |> List.delete_at(from_index)
    |> List.replace_at(to_index, cell)
  end

  @spec downgrade(t) :: t
  defp downgrade(%{type: "h1"} = block), do: %{block | type: "h2"}
  defp downgrade(%{type: "h2"} = block), do: %{block | type: "h3"}
  defp downgrade(%{type: "h3"} = block), do: %{block | type: "p"}
  defp downgrade(%{type: "pre"} = block), do: %{block | type: "p"}
  defp downgrade(%{type: "ul"} = block), do: %{block | type: "p"}
  defp downgrade(%{} = block), do: block

  @spec downgrade_cells(t) :: t
  defp downgrade_cells(%{cells: cells} = block) do
    %{block | cells: Enum.map(cells, &Editor.Cell.transform(&1, "span"))}
  end

  @doc """
  Clones the given block by cloning it's cells and giving it a new id
  """
  @spec clone(t) :: t
  def clone(%__MODULE__{} = block) do
    %{block | id: Editor.Utils.new_id(), cells: Enum.map(block.cells, &Editor.Cell.clone/1)}
  end
end
