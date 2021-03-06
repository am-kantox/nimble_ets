defmodule EasyETS.Tables do
  @moduledoc false
  use GenServer

  defmodule State do
    @moduledoc false
    defstruct opts: [], tables: []
  end

  @spec start_link(opts :: Keyword.t()) :: GenServer.on_start()
  def start_link(opts \\ []),
    do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @spec state() :: %State{}
  def state(), do: GenServer.call(__MODULE__, :state)

  @spec new(definitions :: list() | atom()) :: map()
  def new(definitions) when is_list(definitions),
    do: GenServer.call(__MODULE__, {:new, definitions})

  def new(definitions), do: new([definitions])

  @spec ets_put(name :: atom(), key :: term(), value :: term()) :: :ok
  def ets_put(name, key, value) do
    :ets.insert(name, {key, value})
    :ok
  end

  @spec ets_get(name :: atom(), key :: term(), default :: any()) :: term()
  def ets_get(name, key, default \\ nil) do
    name
    |> ets_fetch(key)
    |> case do
      :error -> default
      {:ok, result} -> result
    end
  end

  @spec ets_fetch(name :: atom(), key :: term()) :: {:ok, term()} | :error
  def ets_fetch(name, key) do
    name
    |> :ets.lookup(key)
    |> case do
      [] -> :error
      [{^key, result}] -> {:ok, result}
      list -> {:ok, for({^key, v} <- list, do: v)}
    end
  end

  @spec ets_del(name :: atom(), key :: term()) :: :ok
  def ets_del(name, key) do
    :ets.delete(name, key)
    :ok
  end

  @spec ets_all(name :: atom()) :: list()
  def ets_all(name), do: name |> :ets.tab2list() |> Enum.map(&elem(&1, 1))

  ##############################################################################
  # Server (callbacks)

  @impl GenServer
  def init(opts), do: {:ok, %State{opts: opts}, {:continue, :tables}}

  @impl GenServer
  def handle_call(:state, _from, state), do: {:reply, state, state}

  @impl GenServer
  def handle_call({:new, definitions}, _from, %State{tables: tables} = state) do
    new_tables = do_tables(definitions)
    {:reply, new_tables, %State{state | tables: [new_tables | tables]}}
  end

  @impl GenServer
  def handle_continue(:tables, %State{opts: opts} = state) do
    tables =
      opts
      |> Keyword.get(:tables, [])
      |> do_tables()

    {:noreply, %State{state | tables: tables}}
  end

  @default_table_options Application.get_env(:nimble_csv, :table_options, [
                           :set,
                           :named_table,
                           :public,
                           {:read_concurrency, true}
                         ])
  @spec do_tables(defs :: list()) :: map()
  defp do_tables(defs) do
    defs
    |> Enum.map(fn
      {t, opts} ->
        {t, [:named_table, :public | opts]}

      t ->
        {t, @default_table_options}
    end)
    |> Enum.map(fn {t, opts} ->
      unless Code.ensure_loaded?(t),
        do: Module.create(t, quote(do: use(EasyETS)), Macro.Env.location(__ENV__))

      {t, opts}
    end)
    |> Enum.into(%{}, fn {t, opts} -> {t, :ets.new(t, opts)} end)
  end
end
