defmodule TriviaPlatform.Questions.ImporterTest do
  use TriviaPlatform.DataCase, async: true

  alias TriviaPlatform.Questions.Importer

  describe "decode_html/1" do
    test "decodes common HTML entities" do
      assert Importer.decode_html("&amp;") == "&"
      assert Importer.decode_html("&lt;tag&gt;") == "<tag>"
      assert Importer.decode_html("&quot;hello&quot;") == "\"hello\""
      assert Importer.decode_html("It&#039;s") == "It's"
      assert Importer.decode_html("caf&eacute;") == "café"
    end

    test "handles text without entities" do
      assert Importer.decode_html("plain text") == "plain text"
    end

    test "handles multiple entities in one string" do
      assert Importer.decode_html("A &amp; B &lt; C") == "A & B < C"
    end
  end
end
