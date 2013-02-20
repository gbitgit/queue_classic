require File.expand_path("../helper.rb", __FILE__)

module TestObject
  extend self
  def no_args; return nil; end
  def one_arg(a); return a; end
  def two_args(a,b); return [a,b]; end
end

# This not only allows me to test what happens
# when a failure occurs but it also demonstrates
# how to override the worker to handle failures the way
# you want.
class TestWorker < QC::Worker
  attr_accessor :failed_count

  def initialize(*args)
    super(*args)
    @failed_count = 0
  end

  def handle_failure(job,e)
    @failed_count += 1
  end
end

class WorkerTest < QCTest
  def test_start_kills_zombies
    QC.enqueue("TestObject")
    QC.lock

    worker = TestWorker.new
    worker.instance_variable_set(:@running, false)

    assert_equal(1, QC.job_count("TestObject"))
    worker.start
    assert_equal(0, QC.job_count("TestObject"))
  end

  def test_kill_zombies_deletes_running_jobs
    QC.enqueue("TestObject")
    QC.lock

    assert_equal(1, QC.job_count("TestObject"))
    QC.kill_zombies
    assert_equal(0, QC.job_count("TestObject"))
  end

  def test_kill_zombies_does_not_delete_enqueued_jobs
    QC.enqueue("TestObject")

    assert_equal(1, QC.job_count("TestObject"))
    QC.kill_zombies
    assert_equal(1, QC.job_count("TestObject"))
  end

  def test_work
    QC.enqueue("TestObject.no_args")
    worker = TestWorker.new("default", 1, false, false, 1)
    assert_equal(1, QC.count)
    worker.work

    sleep(2)
    assert_equal(0, QC.count)
    assert_equal(0, worker.failed_count)
    worker.shutdown
  end

  def test_failed_job
    QC.enqueue("TestObject.not_a_method")
    worker = TestWorker.new("default", 1, false, false, 1)
    worker.work
    sleep(2)
    assert_equal(1, worker.failed_count)
    worker.shutdown
  end

  def test_work_with_no_args
    QC.enqueue("TestObject.no_args")
    worker = TestWorker.new("default", 1, false, false, 1)
    worker.work
    assert_equal(0, worker.failed_count)
    worker.shutdown
  end

  def test_work_with_one_arg
    QC.enqueue("TestObject.one_arg", "1")
    worker = TestWorker.new("default", 1, false, false, 1)
    worker.work
    assert_equal(0, worker.failed_count)
    worker.shutdown
  end

  def test_work_with_two_args
    QC.enqueue("TestObject.two_args", "1", 2)
    worker = TestWorker.new("default", 1, false, false, 1)
    worker.work
    assert_equal(0, worker.failed_count)
    worker.shutdown
  end

  def test_work_custom_queue
    p_queue = QC::Queue.new("priority_queue")
    p_queue.enqueue("TestObject.two_args", "1", 2)
    worker = TestWorker.new("priority_queue", 1, false, false, 1)
    worker.work
    assert_equal(0, worker.failed_count)
    worker.shutdown
  end

  def test_worker_listens_on_chan
    p_queue = QC::Queue.new("priority_queue")
    p_queue.enqueue("TestObject.two_args", "1", 2)
    worker = TestWorker.new("priority_queue", 1, false, true, 1)
    worker.work
    assert_equal(0, worker.failed_count)
    worker.shutdown
  end

  def test_worker_ueses_one_conn
    QC.enqueue("TestObject.no_args")
    worker = TestWorker.new("default", 1, false, false, 1)
    worker.work
    assert_equal(
      1,
      QC::Conn.execute("SELECT count(*) from pg_stat_activity")["count"].to_i,
      "Multiple connections -- Are there other connections in other terminals?"
    )
    worker.shutdown
  end

end
