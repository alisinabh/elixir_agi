defmodule ElixirAgi.Agi do
  @moduledoc """
  This module handles the AGI implementation by reading and writing to/from
  the source.

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
  defmodule HangupError do
    defexception message: "default message"
  end

  require Logger
  alias ElixirAgi.Agi.Result

  defstruct \
    init: nil,
    close: nil,
    reader: nil,
    writer: nil,
    debug: false,
    variables: %{}

  @type t :: ElixirAgi.Agi
  @type reader :: function
  @type writer :: function
  @type init :: function
  @type close :: function

  defmacro log(level, message) do
    quote bind_quoted: [
      level: level,
      message: message
    ] do
      agi = var! agi
      level_str = to_string level
      if((level_str !== "debug") or agi.debug) do
        Logger.bare_log level, "ElixirAgi AGI: #{message}"
      end
    end
  end

  @doc """
  Returns an AGI struct that uses STDIN and STDOUT.
  """
  @spec new(boolean) :: t
  def new(debug \\ false) do
    new(
      fn() -> :ok end,
      fn() -> :ok end,
      fn() -> IO.gets "" end,
      fn(data) -> IO.write data end,
      debug
    )
  end

  @doc """
  Returns an AGI struct.
  """
  @spec new(init, close, reader, writer, boolean) :: t
  def new(init, close, reader, writer, debug) do
    :ok = init.()
    agi = %ElixirAgi.Agi{
      init: init,
      close: close,
      reader: reader,
      writer: writer,
      variables: %{},
      debug: debug
    }
    variables = read_variables agi
    %ElixirAgi.Agi{agi | variables: variables}
  end

  @doc """
  See: https://wiki.asterisk.org/wiki/display/AST/AGICommand_answer
  """
  @spec answer(t) :: Result.t
  def answer(agi) do
    exec agi, "ANSWER"
  end

  @doc """
  See: https://wiki.asterisk.org/wiki/display/AST/AGICommand_hangup
  """
  @spec hangup(t, String.t) :: Result.t
  def hangup(agi, channel \\ "") do
    exec agi, "HANGUP", [channel]
  end

  @doc """
  See: https://wiki.asterisk.org/wiki/display/AST/Asterisk+13+AGICommand_set+variable
  """
  @spec set_variable(t, String.t, String.t) :: Result.t
  def set_variable(agi, name, value) do
    run agi, "SET", ["VARIABLE", "#{name}", "#{value}"]
  end

  @doc """
  See: https://wiki.asterisk.org/wiki/display/AST/Asterisk+13+AGICommand_get+full+variable
  """
  @spec get_full_variable(t, String.t) :: Result.t
  def get_full_variable(agi, name) do
    result = run agi, "GET", ["FULL", "VARIABLE", "${#{name}}"]
     if result.result === "1" do
      [_, var] = Regex.run ~r/\(([^\)]*)\)/, hd(result.extra)
      %Result{result | extra: var}
    else
      %Result{result | extra: nil}
    end
  end

  @doc """
  See: https://wiki.asterisk.org/wiki/display/AST/Application_Dial
  """
  @spec dial(t, String.t, non_neg_integer(), [String.t]) :: Result.t
  def dial(agi, dial_string, timeout_seconds, options) do
    exec agi, "DIAL", [
      dial_string,
      to_string(timeout_seconds),
      Enum.join(options, ",")
    ]
  end

  @doc """
  See: https://wiki.asterisk.org/wiki/display/AST/Application_Wait
  """
  @spec wait(t, non_neg_integer()) :: Result.t
  def wait(agi, seconds) do
    exec agi, "WAIT", [seconds]
  end

  @doc """
  See: https://wiki.asterisk.org/wiki/display/AST/Application_AMD
  """
  @spec amd(
    t,
    non_neg_integer,
    non_neg_integer,
    non_neg_integer,
    non_neg_integer,
    non_neg_integer,
    non_neg_integer,
    non_neg_integer,
    non_neg_integer,
    non_neg_integer
  ) :: Result.t
  def amd(
    agi,
    initial_silence,
    greeting,
    after_greeting_silence,
    total_time,
    min_word_length,
    between_words_silence,
    max_words,
    silence_threshold,
    max_word_length
  ) do
    exec agi, "AMD", [
      initial_silence,
      greeting,
      after_greeting_silence,
      total_time,
      min_word_length,
      between_words_silence,
      max_words,
      silence_threshold,
      max_word_length
    ]
  end

  @doc """
  See: https://wiki.asterisk.org/wiki/display/AST/Asterisk+13+AGICommand_stream+file
  """
  @spec stream_file(t, String.t, String.t) :: Result.t
  def stream_file(agi, file, escape_digits \\ "") do
    run agi, "STREAM", ["FILE", file, escape_digits]
  end

  @doc """
  See: TODO: get from wiki
  """
  @spec control_stream_file(t, String.t, String.t, Integer.t, String.t, String.t, String.t) :: Result.t
  def control_stream_file(agi, file, escape_digits \\ "", offset \\ 0, forward_digits \\ "", rewind_digits \\ "", pause_digits \\ "") do
    run agi, "CONTROL STREAM", ["FILE", file, escape_digits, offset, forward_digits, rewind_digits, pause_digits]
  end

  @doc """
  See: https://wiki.asterisk.org/wiki/display/AST/AGICommand_exec
  """
  @spec exec(t, String.t, [String.t]) :: Result.t
  def exec(agi, application, args \\ []) do
    run agi, "EXEC", [application|args]
  end

  @spec run(t, String.t, [String.t]) :: Result.t
  def run(agi, cmd, args) do
    args = for a <- args, do: ["\"", to_string(a), "\" "]
    cmd = ["\"", cmd, "\" "|args]
    :ok = write agi, cmd
    Result.new read(agi)
  end

  @spec read_variables(t, Map.t) :: Map.t
  def read_variables(agi, vars \\ %{}) do
    log :debug, "Reading next variable"
    line = read agi
    cond do
      String.length(line) < 2 -> vars
      true ->
        [k, v] = String.split line, ":", parts: 2
        vars = Map.put vars, String.strip(k), String.strip(v)
        read_variables agi, vars
    end
  end

  defp write(agi, data) do
    log :debug, "Writing #{data}"
    :ok = agi.writer.([data, "\n"])
    :ok
  end

  defp read(agi) do
    line = agi.reader.()
    {line, _} = String.split_at line, -1
    log :debug, "Read #{line}"
    case line do
      "HANGUP" <> _rest ->
        agi.close.()
        raise HangupError, "hangup"
      _ -> line
    end
  end
end
