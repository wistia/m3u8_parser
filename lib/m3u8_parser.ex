defmodule M3u8Parser do
  @doc """
  Read the Media Playlist at `path` and parse out the duration and size of each media segment.
  See the [HLS specification](https://tools.ietf.org/html/draft-pantos-http-live-streaming-20) for
  more info
  """
  def parse_segments!(path) do
    {:ok, res} =
      File.open(path, [:read], fn f ->
        IO.stream(f, :line)
        |> Enum.reduce(%{state: nil}, fn line, acc -> do_parse(acc, line) end)
        |> validate_done!
        |> Map.get(:segments)
      end)
    res
  end

  defp validate_done!(acc = %{state: :done}), do: acc
  defp validate_done!(%{state: state}), do: raise "Unexpected state! Expected :done but got #{inspect state}"

  defp do_parse(%{state: :done}, _line), do: raise "Unexpected state! Already reached end of M3U8"
  defp do_parse(acc = %{state: nil}, line) do
    cond do
      is_match?(line, "#EXTM3U") -> put_in(acc[:state], :top)
    end
  end
  defp do_parse(acc = %{state: :top}, line) do
    cond do
      is_match?(line, "#EXTINF")          -> parse_extinf(acc, line)
      is_match?(line, "#EXT-X-BYTERANGE") -> parse_byterange(acc, line)
      is_match?(line, "#EXT-X-ENDLIST")   -> put_in(acc[:state], :done)
      is_match?(line, "#")                -> acc # ignore other tags and comments
    end
  end
  defp do_parse(acc = %{state: :defsegment}, line) do
    cond do
      is_match?(line, "#EXTINF")          -> parse_extinf(acc, line)
      is_match?(line, "#EXT-X-BYTERANGE") -> parse_byterange(acc, line)
      is_match?(line, "#EXT-X-ENDLIST")   -> put_in(acc[:state], :done)
      is_match?(line, "#")                -> acc # ignore other tags and comments
      true                                -> compile_segment_and_go_to_top(acc) # we saw a URI
    end
  end

  defp parse_extinf(acc, line) do
    {duration, _title} = parse_extinf_line(line)
    acc = put_in(acc[:state], :defsegment)
    pend(acc, duration: duration)
  end

  defp parse_extinf_line(line) do
    [_, tail] = String.split(line, ":", parts: 2)
    [duration, title] = String.split(tail, ",", parts: 2)
    {duration, _} = Float.parse(duration)
    title = trim_trailing_new_line(title)
    {duration, title}
  end

  def parse_byterange(acc, line) do
    {bytes, _offset} = parse_byterange_line(line)
    acc = put_in(acc[:state], :defsegment)
    pend(acc, bytes: bytes)
  end

  defp parse_byterange_line(line) do
    [_, tail] = String.split(line, ":", parts: 2)
    case String.split(tail, "@", parts: 2) do
      [bytes, offset] ->
        {bytes, _} = Integer.parse(bytes)
        {offset, _} = Integer.parse(offset)
        {bytes, offset}

      [bytes] ->
        {bytes, _} = Integer.parse(bytes)
        {bytes, nil}
    end
  end

  defp compile_segment_and_go_to_top(acc) do
    compiled = Enum.into(acc[:pending], %{})
    update_in(acc[:segments], fn segments -> (segments || []) ++ [compiled] end)
    |> put_in([:pending], [])
    |> put_in([:state], :top)
  end

  defp is_match?(line, match), do: String.starts_with?(line, match)

  defp pend(acc, keyword) do
    update_in(acc[:pending], fn pend -> (pend || []) ++ keyword end)
  end

  defp trim_trailing_new_line(string) do
    String.replace(string, ~r/\r?\n$/, "")
  end
end
