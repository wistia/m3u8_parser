defmodule M3u8ParserTest do
  use ExUnit.Case
  doctest M3u8Parser

  @m3u8 Path.expand("../a.m3u8", __ENV__.file())

  test "parse_segments!/1" do
    segments = M3u8Parser.parse_segments!(@m3u8)

    Enum.each(segments, fn segment ->
      %{duration: duration, bytes: bytes} = segment
      assert duration > 0
      assert bytes > 0
    end)

    assert length(segments) == 52
  end
end
