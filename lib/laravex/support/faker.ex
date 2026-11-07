defmodule Laravex.Support.Faker do
  @moduledoc """
  Tiny deterministic-enough fake data helpers for factories/seeders.

      Laravex.Support.Faker.name()
      Laravex.Support.Faker.email()
      Laravex.Support.Faker.sentence()
  """

  @first ~w(Ada Beau Cora Drew Eden Flynn Gia Hugo Isla Jules Kai Lia Milo Nora Otto Piper Quinn Remy Sage Tess)
  @last ~w(Baker Chen Diaz Evans Ford Gupta Hayes Ito Jones Khan Lee Moss Ng Ortiz Patel Quinn Reed Sato Tran White)
  @words ~w(alpha brave calm delta eager fresh gentle happy ideal jolly keen lively merry noble open proud quiet ready steady true vivid warm)

  def name do
    Enum.random(@first) <> " " <> Enum.random(@last)
  end

  def first_name, do: Enum.random(@first)
  def last_name, do: Enum.random(@last)

  def email do
    local =
      (first_name() <> "." <> last_name() <> Integer.to_string(:rand.uniform(9999)))
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9.]+/, "")

    local <> "@example.test"
  end

  def word, do: Enum.random(@words)

  def sentence(words \\ 8) do
    1..max(words, 1)
    |> Enum.map(fn _ -> word() end)
    |> Enum.join(" ")
    |> String.capitalize()
    |> Kernel.<>(".")
  end

  def paragraph(sentences \\ 3) do
    1..max(sentences, 1)
    |> Enum.map(fn _ -> sentence(:rand.uniform(10) + 4) end)
    |> Enum.join(" ")
  end

  def boolean, do: :rand.uniform(2) == 1

  def number(min \\ 1, max \\ 100), do: Enum.random(min..max)

  def uuid, do: Laravex.Support.Str.uuid()
end
