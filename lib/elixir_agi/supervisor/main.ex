defmodule ElixirAgi.Supervisor.Main do
  @moduledoc """
  Main supervisor.

  Copyright 2015 Marcelo Gornstein <marcelog@gmail.com>

  Licensed under the Apache License, Version 2.0 (the "License");
  you may not use this file except in compliance with the License.
  You may obtain a copy of the License at
      http://www.apache.org/licenses/LICENSE-2.0

  Unless required by applicable law or agreed to in writing, software
  distributed under the License is distributed on an "AS IS" BASIS,
  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
  See the License for the specific language governing permissions and
  limitations under the License.
  """
  use Supervisor
  require Logger

  @doc """
  Starts the supervisor
  """
  @spec start_link() :: Supervisor.on_start
  def start_link do
    Supervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc """
  Supervisor callback.
  """
  @spec init([]) :: {:ok, tuple}
  def init([]) do
    children = [
      supervisor(ElixirAgi.Supervisor.Agi, [], [
        restart: :permanent,
        shutdown: :infinity
      ]),
      supervisor(ElixirAgi.Supervisor.FastAgi, [], [
        restart: :permanent,
        shutdown: :infinity
      ])
    ]

    supervise(children, strategy: :one_for_one)
  end
end