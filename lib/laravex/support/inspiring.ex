defmodule Laravex.Support.Inspiring do
  @moduledoc """
  Port of Laravel's Inspiring quotes helper.
  """

  @quotes [
    "Act only according to that maxim whereby you can, at the same time, will that it should become a universal law. - Immanuel Kant",
    "The only way to do great work is to love what you do. - Steve Jobs",
    "Simplicity is the ultimate sophistication. - Leonardo da Vinci",
    "Well begun is half done. - Aristotle",
    "It always seems impossible until it's done. - Nelson Mandela"
  ]

  def quote_text do
    Enum.random(@quotes)
  end
end
