defmodule Laravex.Mail.SendMailJob do
  @moduledoc false
  use Laravex.Queue.Job, queue: true

  def handle([mailable]) do
    Laravex.Mail.Mailer.deliver_now(mailable)
  end
end

defmodule Laravex.Mail.ShouldQueue do
  @moduledoc """
  Queue mailable delivery (Laravel `ShouldQueue` for mail).

      defmodule App.Mail.Welcome do
        use Laravex.Mail.Mailable
        use Laravex.Mail.ShouldQueue
      end
  """

  defmacro __using__(_opts \\ []) do
    quote do
      def via_queue?, do: true
      defoverridable via_queue?: 0
    end
  end
end
