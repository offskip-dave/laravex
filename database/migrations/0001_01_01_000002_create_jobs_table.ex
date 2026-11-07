defmodule Database.Migrations.CreateJobsTable do
  @moduledoc """
  Port of 0001_01_01_000002_create_jobs_table.php
  """

  def up do
    [
      {:create, "jobs",
       [
         {:id, :bigserial, primary: true},
         {:string, "queue", index: true},
         {:long_text, "payload"},
         {:unsigned_small_integer, "attempts"},
         {:unsigned_integer, "reserved_at", nullable: true},
         {:unsigned_integer, "available_at"},
         {:unsigned_integer, "created_at"}
       ]},
      {:create, "job_batches",
       [
         {:string, "id", primary: true},
         {:string, "name"},
         {:integer, "total_jobs"},
         {:integer, "pending_jobs"},
         {:integer, "failed_jobs"},
         {:long_text, "failed_job_ids"},
         {:medium_text, "options", nullable: true},
         {:integer, "cancelled_at", nullable: true},
         {:integer, "created_at"},
         {:integer, "finished_at", nullable: true}
       ]},
      {:create, "failed_jobs",
       [
         {:id, :bigserial, primary: true},
         {:string, "uuid", unique: true},
         {:string, "connection"},
         {:string, "queue"},
         {:long_text, "payload"},
         {:long_text, "exception"},
         {:timestamp, "failed_at", use_current: true}
       ]}
    ]
    |> Laravex.Database.Migrator.apply()
  end

  def down do
    Laravex.Database.Migrator.drop(["jobs", "job_batches", "failed_jobs"])
  end
end
