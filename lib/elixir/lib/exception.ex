# Some exceptions implement `message/1` instead of `exception/1` mostly
# for bootstrap reasons. It is recommended for applications to implement
# `exception/1` instead of `message/1` as described in `defexception/3` docs.

defexception RuntimeError,      message: "runtime error"
defexception ArgumentError,     message: "argument error"
defexception ArithmeticError,   message: "bad argument in arithmetic expression"
defexception SystemLimitError,  message: "a system limit has been reached"

defexception SyntaxError, [file: nil, line: nil, description: "syntax error"] do
  def message(exception) do
    Exception.format_file_line(Path.relative_to_cwd(exception.file), exception.line) <>
      exception.description
  end
end

defexception TokenMissingError, [file: nil, line: nil, description: "expression is incomplete"] do
  def message(exception) do
    Exception.format_file_line(Path.relative_to_cwd(exception.file), exception.line) <>
      exception.description
  end
end

defexception CompileError, [file: nil, line: nil, description: "compile error"] do
  def message(exception) do
    Exception.format_file_line(Path.relative_to_cwd(exception.file), exception.line) <>
      exception.description
  end
end

defexception BadFunctionError, [actual: nil] do
  def message(exception) do
    "expected a function, got: #{inspect(exception.actual)}"
  end
end

defexception MatchError, [actual: nil] do
  def message(exception) do
    "no match of right hand side value: #{inspect(exception.actual)}"
  end
end

defexception CaseClauseError, [actual: nil] do
  def message(exception) do
    "no case clause matching: #{inspect(exception.actual)}"
  end
end

defexception TryClauseError, [actual: nil] do
  def message(exception) do
    "no try clause matching: #{inspect(exception.actual)}"
  end
end

defexception BadArityError, [function: nil, args: nil] do
  def message(exception) do
    args = Enum.map_join(exception.args, ", ", &inspect/1)
    "bad arity error: #{inspect(exception.function)} called with (#{args})"
  end
end

defexception UndefinedFunctionError, [module: nil, function: nil, arity: nil] do
  def message(exception) do
    if exception.function do
      formatted = Exception.format_mfa exception.module, exception.function, exception.arity
      "undefined function: #{formatted}"
    else
      "undefined function"
    end
  end
end

defexception FunctionClauseError, [module: nil, function: nil, arity: nil] do
  def message(exception) do
    if exception.function do
      formatted = Exception.format_mfa exception.module, exception.function, exception.arity
      "no function clause matching in #{formatted}"
    else
      "no function clause matches"
    end
  end
end

defexception Protocol.UndefinedError, [protocol: nil, value: nil, description: nil] do
  def message(exception) do
    msg = "protocol #{inspect exception.protocol} not implemented for #{inspect exception.value}"
    if exception.description do
      msg <> ", " <> exception.description
    else
      msg
    end
  end
end

defexception ErlangError, [original: nil] do
  def message(exception) do
    "erlang error: #{inspect(exception.original)}"
  end
end

defexception KeyError, key: nil do
  def message(exception) do
    "key not found: #{inspect exception.key}"
  end
end

defexception Enum.OutOfBoundsError, message: "out of bounds error"

defexception Enum.EmptyError, message: "empty error"

defexception File.Error, [reason: nil, action: "", path: nil] do
  def message(exception) do
    formatted = iolist_to_binary(:file.format_error(reason exception))
    "could not #{action exception} #{path exception}: #{formatted}"
  end
end

defexception File.CopyError, [reason: nil, action: "", source: nil, destination: nil, on: nil] do
  def message(exception) do
    formatted = iolist_to_binary(:file.format_error(reason exception))
    location  = if on = on(exception), do: ". #{on}", else: ""
    "could not #{action exception} from #{source exception} to " <>
      "#{destination exception}#{location}: #{formatted}"
  end
end

defmodule Exception do
  @moduledoc """
  Convenience functions to work with and pretty print
  exceptions and stacktraces.

  Notice that stacktraces in Elixir are updated on errors.
  For example, at any given moement, `System.stacktrace`
  will return the stacktrace for the last error that ocurred
  in the current process.

  That said, many of the functions in this module will
  automatically calculate the stacktrace based on the caller,
  when invoked without arguments, changing the value of
  `System.stacktrace`. If instead you want to format the
  stacktrace of the latest error, you should instead explicitly
  pass the `System.stacktrace` as argument.
  """

  @doc """
  Normalizes an exception, converting Erlang exceptions
  to Elixir exceptions.

  It takes the `kind` spilled by `catch` as an argument and
  normalizes only `:error`, returning the untouched payload
  for others.
  """
  def normalize(:error, exception), do: normalize(exception)
  def normalize(_kind, other), do: other

  @doc """
  Normalizes an exception, converting Erlang exceptions
  to Elixir exceptions.

  Useful when interfacing Erlang code with Elixir code.
  """
  def normalize(exception) when is_exception(exception) do
    exception
  end

  def normalize(:badarg) do
    ArgumentError[]
  end

  def normalize(:badarith) do
    ArithmeticError[]
  end

  def normalize(:system_limit) do
    SystemLimitError[]
  end

  def normalize({ :badarity, { fun, args } }) do
    BadArityError[function: fun, args: args]
  end

  def normalize({ :badfun, actual }) do
    BadFunctionError[actual: actual]
  end

  def normalize({ :badmatch, actual }) do
    MatchError[actual: actual]
  end

  def normalize({ :case_clause, actual }) do
    CaseClauseError[actual: actual]
  end

  def normalize({ :try_clause, actual }) do
    TryClauseError[actual: actual]
  end

  def normalize(:undef) do
    { mod, fun, arity } = from_stacktrace(:erlang.get_stacktrace)
    UndefinedFunctionError[module: mod, function: fun, arity: arity]
  end

  def normalize(:function_clause) do
    { mod, fun, arity } = from_stacktrace(:erlang.get_stacktrace)
    FunctionClauseError[module: mod, function: fun, arity: arity]
  end

  def normalize({ :badarg, payload }) do
    ArgumentError[message: "argument error: #{inspect(payload)}"]
  end

  def normalize(other) do
    ErlangError[original: other]
  end

  @doc """
  Receives a tuple representing a stacktrace entry and formats it.
  """
  def format_stacktrace_entry(entry)

  # From Macro.Env.stacktrace
  def format_stacktrace_entry({ module, :__MODULE__, 0, location }) do
    format_location(location) <> inspect(module) <> " (module)"
  end

  # From :elixir_compiler_*
  def format_stacktrace_entry({ _module, :__MODULE__, 1, location }) do
    format_location(location) <> "(module)"
  end

  # From :elixir_compiler_*
  def format_stacktrace_entry({ _module, :__FILE__, 1, location }) do
    format_location(location) <> "(file)"
  end

  def format_stacktrace_entry({module, fun, arity, location}) do
    format_application(module) <> format_location(location) <> format_mfa(module, fun, arity)
  end

  def format_stacktrace_entry({fun, arity, location}) do
    format_location(location) <> format_fa(fun, arity)
  end

  defp format_application(module) do
    case :application.get_application(module) do
      { :ok, app } -> "(" <> atom_to_binary(app) <> ") "
      :undefined   -> ""
    end
  end

  @doc """
  Formats the stacktrace.

  A stacktrace must be given as an argument. If not, this function
  calculates a new stacktrace based on the caller and formats it. As
  a consequence, the value of `System.stacktrace` is changed.
  """
  def format_stacktrace(trace // nil) do
    trace = trace || try do
      throw(:stacktrace)
    catch
      :stacktrace -> Enum.drop(:erlang.get_stacktrace, 1)
    end

    case trace do
      [] -> "\n"
      s  -> "    " <> Enum.map_join(s, "\n    ", &format_stacktrace_entry(&1)) <> "\n"
    end
  end

  @doc """
  Formats the caller, i.e. the first entry in the stacktrace.

  A stacktrace must be given as an argument. If not, this function
  calculates a new stacktrace based on the caller and formats it. As
  a consequence, the value of `System.stacktrace` is changed.

  Notice that due to tail call optimization, the stacktrace
  may not report the direct caller of the function.
  """
  def format_caller(trace // nil) do
    trace = trace || try do
      throw(:stacktrace)
    catch
      :stacktrace -> Enum.drop(:erlang.get_stacktrace, 1)
    end

    if entry = Enum.at(trace, 1) do
      format_stacktrace_entry(entry)
    else
      "nofile:0: "
    end
  end

  @doc """
  Receives an anonymous function and arity and formats it as
  shown in stacktraces. The arity may also be a list of arguments.

  ## Examples

      Exception.format_fa(fn -> end, 1)
      #=> "#Function<...>/1"

  """
  def format_fa(fun, arity) do
    if is_list(arity) do
      inspected = lc x inlist arity, do: inspect(x)
      "#{inspect fun}(#{Enum.join(inspected, ", ")})"
    else
      "#{inspect fun}/#{arity}"
    end
  end

  @doc """
  Receives a module, fun and arity and formats it
  as shown in stacktraces. The arity may also be a list
  of arguments.

  ## Examples

      iex> Exception.format_mfa Foo, :bar, 1
      "Foo.bar/1"
      iex> Exception.format_mfa Foo, :bar, []
      "Foo.bar()"
      iex> Exception.format_mfa nil, :bar, []
      "nil.bar()"

  """
  def format_mfa(module, fun, arity) do
    fun =
      case inspect(fun) do
        << ?:, erl :: binary >> -> erl
        elixir -> elixir
      end

    if is_list(arity) do
      inspected = lc x inlist arity, do: inspect(x)
      "#{inspect module}.#{fun}(#{Enum.join(inspected, ", ")})"
    else
      "#{inspect module}.#{fun}/#{arity}"
    end
  end

  @doc """
  Formats the given file and line as shown in stacktraces.
  If any of the values are nil, they are omitted.

  ## Examples

      iex> Exception.format_file_line("foo", 1)
      "foo:1: "

      iex> Exception.format_file_line("foo", nil)
      "foo: "

      iex> Exception.format_file_line(nil, nil)
      ""

  """
  def format_file_line(file, line) do
    if file do
      if line && line != 0 do
        "#{file}:#{line}: "
      else
        "#{file}: "
      end
    else
      ""
    end
  end

  defp format_location(opts) do
    format_file_line Keyword.get(opts, :file), Keyword.get(opts, :line)
  end

  defp from_stacktrace([{ module, function, args, _ }|_]) when is_list(args) do
    { module, function, length(args) }
  end

  defp from_stacktrace([{ module, function, arity, _ }|_]) do
    { module, function, arity }
  end

  defp from_stacktrace(_) do
    { nil, nil, nil }
  end
end
