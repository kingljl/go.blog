今天有同事问起，如何并发执行任务，同时保持让结果有序。

我记得以前写过一段代码，想起来很精妙，应该 share 出来。

    type task struct {
        sync.WaitGroup
    }
    func main() {
        for t := range <-task {
            sendToWorker(ch, t)
            sendToKeepOrder(fifo, t)
        }

        for t := range <-fifo {
            t.wait()
        }
    }
    func worker(ch) {
        for t := range ch {
            t.Done()
        }
    }
    
同时把任务往两个队列里面扔，一个用于实现并发，另一个用于实现先进先出。同时用一个 WaitGroup 来保序。

最早这段代码出现在这里

https://github.com/pingcap/tidb/pull/6323#discussion_r193763230

更早的启发应该来源于这里的一个场景，往各个 region 发请求需要并行，而结果又需要是按发送顺序返回。

https://github.com/pingcap/tidb/pull/2804/files#diff-c27388ffb48c6f6eaeefe07dd3243530R406
