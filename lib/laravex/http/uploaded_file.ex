defmodule Laravex.Http.UploadedFile do
  @moduledoc "Uploaded file from a multipart request."

  defstruct [:filename, :content_type, :size, :contents, :path]

  def new(attrs) when is_map(attrs) do
    contents = Map.get(attrs, :contents) || Map.get(attrs, "contents") || ""

    %__MODULE__{
      filename: Map.get(attrs, :filename) || Map.get(attrs, "filename"),
      content_type: Map.get(attrs, :content_type) || Map.get(attrs, "content_type"),
      size: Map.get(attrs, :size) || Map.get(attrs, "size") || byte_size(contents),
      contents: contents,
      path: Map.get(attrs, :path) || Map.get(attrs, "path")
    }
  end

  def extension(%__MODULE__{filename: name}) when is_binary(name) do
    name |> Path.extname() |> String.trim_leading(".") |> String.downcase()
  end

  def extension(_), do: ""

  def image?(%__MODULE__{} = file) do
    extension(file) in ~w(jpg jpeg png gif webp bmp svg) or
      String.starts_with?(to_string(file.content_type || ""), "image/")
  end

  def mime_type(%__MODULE__{content_type: type}) when is_binary(type), do: type
  def mime_type(_), do: "application/octet-stream"

  def size_kb(%__MODULE__{size: size}) when is_integer(size), do: div(size, 1024)
  def size_kb(_), do: 0

  def store(%__MODULE__{} = file, directory \\ "", disk \\ "public") do
    Laravex.Filesystem.Storage.store(file, directory, disk)
  end
end
