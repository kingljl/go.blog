《Calvin: Fast Distributed Transactions for Partitioned Database Systems》

# Abstract

> Calvin is a practical transaction scheduling and data replication layer that uses a deterministic ordering guarantee to significantly reduce the normally prohibitive contention costs associated with distributed transactions.

事务调度和数据副本层，通过确定 order 的保障，极大的减少了分布式事务存在的竞争问题。

线性扩展，无单点问题

> By replicating transaction inputs rather than effects, Calvin is also able to support multiple consistency levels—including Paxosbased strong consistency across geog

replicate 的时事务的输入，而不是事务的 effect。这个 effect 怎么理解呢，就是说，复制的是操作，而不是状态。

# 1. Background and introduction

前面正确的废话都跳过了

> Calvin is designed to run alongside a non-transactional storage system, transforming it into a shared-nothing (near-)linearly scalable database system that provides high availability1 and full ACID transactions.

calvin 是设计成运行在不支持事务的存储层之上的。它是存储层之上，提供了一层事务调度层。

> The key technical feature that allows for scalability in the face of distributed transactions is a deterministic locking mechanism that enables the elimination of distributed commit protocols.

最关键的技术是，使用确定的锁机制，消除了分布式提交协议。这里面所谓分布式提交协议，其实指的就是 2PC。

## 1.1 The cost of distributed transactions

2PC 要求所有的成员参与，走多轮网络。这个协议的设计，整个过程其实是锁住的。如果有 popular record 的情况，这会极大的降低系统吞吐。想想这里是不是？

> We refer to the total duration that a transaction holds its locks which includes the duration of any required commit protocol as the transaction’s contention footprint

事务持有锁的时间，这里定义了一个 contention footprint。本文的假设是悲观协议，所以算的是锁的时间。假设是乐观并发协议，一旦事务 abort，影响其实是严重的，

## 1.2 Consistent replication

一致性复制协议这里就特指 paxos 了，就像前面分布式提交协议其实说的 2PC 一样。

## 1.3 Achieving agreement without increasing contention

> when multiple machines need to agree on how to handle a particular transaction, they do it outside of transactional boundaries

这句废话是说，假设多个机器，它们已经对于某个事务如何处理，达成共识了，那就没有了加锁呀，并发控制呀，这些事情了。

必须完全严格地按 plan 描述的去执行。node 挂了这类问题，并不会使得事务 abort。挂了恢复，继续执行，只要事务的执行是确定的。

就是说，只要把所有事务定好序，把它们将要如何执行事先确定下来，后面就严格地执行就好了，过程就跟重放 log 其实是一样的。而 log 有 paxos 来保证了。

所以事情就变成如何保证 determinism 了。

> Calvin uses a deterministic locking protocol based on one we introduced in previous work [28]

calvin 使用了一个确定的锁协议，在之前的论文里面讲过。

calvin 这种方式，完全地干掉了 2PC 的过程。(关键点：calvin 是干掉了事务提交阶段的 2PC 开销，但是它干掉 2PC 的代价是引入事务的定序过程，而给并发事务定序这一步是有额外开销的)

主要贡献：

* 设计了一个事务调度和复制层，可以将不支持事务的存储系统，变成一个水平扩展，高可用，强一致，完全支持 ACID 事务的系统
* 一个靠谱的 deterministic 的并发控制协议的实现，比之前的方法更 scalable，并且无单点故障
* 快速 checkpoint 模式，跟 determinism 保证加在一起，可以完全干掉 REDO log 以及它相应的开销

#  2. Deterministic database systems

需要分布式提交协议，是因为事务需要一个原子性保证，并且是持久化的：要么都成功，要么都失败。

> Events that preven a node from committing its local changes fall into two categories: nondeterministic events and deterministic events

导致某个节点提交它本地 change 失败的事件可以分为两类：一类是不确定事件，比如节点挂了。另一类是确定事件，事务的逻辑比如遇到锁。事务在 nondeterministic 事件里面，是不应该 abort 的。

假设因为 nondeterministic 事件让整个系统卡住，这设计是很傻逼的。题外话，读到这里，我想举个很傻逼的例子，2PC 阶段，coordinator 把请求发给所有的 worker，所有 worker 都回复 yes 了，然后 coordinator 挂掉了。整个系统就卡住了：所有 worker 只能等待 coordinator 节点恢复过来。

如果协议设计的是 deterministic 的，那么遇上 nondeterministic 事件时，replica 起来继续执行就 ok 了。

>  The only problem is that replicas need to be going through the same sequence of database states in order for a replica to immediately replace a failed node in the middle of a transaction.

关键点只需要顺序是确定的，在事务过程中挂掉，让 replica 替换掉原 node，继续执行就是了。

> Synchronously replicating every database state change would have far too high of an overhead to be feasible. Instead deterministic database systems synchronously replicate batches of transaction requests.

复制所有数据库的状态变化，overhead 太重了。只复制 batch 的事务请求。

传统数据库里，这样复制事务请求是不行的，因为会有事务并发问题：事务并发执行顺序，需要跟某个串行执行顺序一致。然而，假设先走一个加锁排序的操作，后面的执行顺序就可以保证 deterministic 了。

顺序定了之后，replica node 只需要同步就行了。同样的操作会得到相同的结果。并且遇到故障恢复也无所谓，事务并不 abort。在事务处理的最后，不需要执行一个分布式提交。

# 3. SYSTEM ARCHITECTURE

> Calvin organizes the partitioning of data across the storage systems on each node, and orchestrates all network communication that must occur betwee nodes in the course of transaction execution.

calvin 将数据 partition 到存储系统的各个节点上面，并且编排事务执行时的节点间网络通信。

calvin 分成三层的不同子系统：

* sequencing 层: 将收到的事务请求进行全局输入排序
* scheduler 层：事务编排，使得事务可以并行执行，而执行结果又是等价于某种串行执行顺序的
* storage 层：处理物理的数据分布

> Each node in a Calvin deployment typically runs one partition of each layer

这三层都是水平扩展的，分布在整集群的 share-nothing 节点上面。（这里有个疑问，如此分层，并且各层分布式，会使各层之间的网络通信开销很高。就像上一层的某个 node，要跟下一层的另一个 node 通信，而不是在同 node 上面）

> By separating the replication mechanism, transactional functionality and concurrency control (in the sequencing and scheduling layers) from the storage system, the design of Calvin deviates significantly from traditional database design which is highly monolithic, with physical access methods, buffer manager, lock manager, and log manager highly integrated and cross-reliant. 

事务功能，并发控制，这些是跟存储系统分离的。这样子 calvin 跟传统的数据库很不一样：在物理访问，缓存管理，锁管理，日志管理等方面。

##  3.1 Sequencer and replication

一个最简单的 sequencer 就是把所有请求都发到一个 node 上面，log 下来，然后按 timestamp 顺序 forward 到后面节点上去。但是这样问题是，一个有单点故障，另一个集群负载的上限，就是单个节点处理能力。

> Calvin’s sequencing layer is distributed across all system replicas, and also partitioned across every machine within each replica.

calvin 里面这个东西是分布式的。

> Calvin divides time into 10-millisecond epochs during which every machine’s sequencer component collects transaction requests from clients. At the end of each epoch, all requests that have arrived at a sequencer node are compiled into a batch.

sequencer 组件以 10ms 为单位，收集 client 请求。每个 epoch 结束的时候，到达一个 node 的 sequencer 上面的请求形成一个 batch。

每个 batch 写副本成功以后，向 scheduler 发消息，包括以下信息：

1) sequencer 的唯一节点 ID 

2) epoch number (即每 10ms 一次的这个)

3) 所有需要多个 recipient 参与的事务输入

这样子每个 scheduler 就可以将该 epoch 来自所有 sequencer 的交错的事务的 batch 汇集到一起。

### 3.1.1 Synchronous and asynchronous replication

calvin 支持异步复制和 基于 paxos 的同步复制两种模式。两种模式下，节点都是分成了 replication groups。每个 replication group 都包含一个分片的所有副本。

异步复制模式下，是设计成主从。优点是极低延迟，缺点是在遇到错误时，容错处理的复杂度显著增加。(不想细节了，在我看来，异步模式绝逼不靠谱的)。然后就是 paxos 同步模式。

> since this synchronization step does not extend contention footprints, transactional throughput is completely unaffected by this preprocessing step

注意，这一步的同步过程，是不会对事务的竞争导致的延时，产生半毛钱的影响的。也就是顶请求多影响请求的响应延迟，不会影响事务吞吐。
作者在这里丢了一个图表，同数据中心，ping 延迟 1ms 跟 amazon 的 Northern California 到 Ireland 数据中心，ping 延迟 100-170ms 的情况，总体事务吞吐没受影响。

## 3.2 Scheduler and concurrency control

一旦走到存储层，所有事情都必须是确定的了。

> Both the logging and concurrency protocols have to be completely logical, referring only to record keys rather than physical data structures.

logging 只能够是 logical 的 logging。由于数据库的状态可以完全由输入确定，逻辑 logging 很简单。在 sequencing 层 logging，并且定期的在 storage 层做 checkpoint。

这里又有一个细节，阻止 phantom updates 一般需要锁住一个 range 的 keys，这个操作发生在物理数据上面的上锁，而 scheduler 只能访问到（从 sequencer 汇总过来的）逻辑 record 信息，作者没细讲怎么处理，丢了另外一篇 paper：

>  To handle this case, Calvin could use an approach proposed recently for another unbundled database system by creating virtual resources that can be logically locked in the transactional layer [20]

calvin 的 deterministic 锁管理器，是 partition 到整个 scheduler 层的。每个 node 的 scheduler 只负责该 node 的存储组件上面的 lock。

> each node’s scheduler is only responsible for locking records that are stored at that node’s storage component even for transactions that access records stored on other nodes.

锁协议类似于严格的两阶段锁，加了一点点约束。

* 事务 A 和 B，都需要在资源 R 上面加排它锁，如果事务 A 先于 B，则 A 必须先于 B 在资源 R 上加锁。calvin 把这个丢到单线程做了。

> All transactions are therefore required to declare their full read/write sets in advance

**每个事务都必须提前声明，它所有的读/写的请求访问的集合** (我认为这是一个非常大的约束）

* 锁管理器 grant 每个锁给事务的顺序，必须严格的按照事务请求锁的顺序

> Once a transaction has acquired all of its locks under this protocol (and can therefore be safely executed in its entirety) it is handed off to a worker thread to be executed. 

一旦一个事务拿到它所有需要的锁之后，就可以丢给后台 worker 去执行了。

worker 线程执行事务分为五个阶段：

1. 读/写 集合分析
2. 执行本地读
3. 远程读
4. 收集远程读结果
5. 执行事务逻辑并且 write

### 3.2.1 Dependent transactions

>  Calvin’s deterministic locking protocol requires advance knowledge of all transactions’ read/write sets before transaction execution can begin

由于这个限制，对于需要先读，才能知道完整 读/写 集合的事务，也就是有依赖的事务，calvin 是不支持的。这一节里面写了一点点特例，说 calvin 能支持的情况。

> The idea is for dependent transactions to be preceded by an inexpensive, low-isolation, unreplicated, read-only reconnaissance query that performs all the necessary reads to discover the transaction’s full read/write set

其实是对前面的读 query 先执行了一遍，得到读/写集合之后，再去构建。这里面会存在好几个问题，一个是每一遍预读的操作，一定需要是一个非常轻量，所以论文说要求 inexpensive, low-isolation, unreplicated

另外一个是，如果构建读/写集合期间，有其它的事务去修改了数据，那读到的就是失效了，构造的读/写集合也就是失效的。如果这样子，就会违反之前说的，事务写 storage 层之前 deterministic 的要求。所以呢，这里又一个约束是要求 read-only reconnaissance query

它居然还花了一段文字，说次级索引的例子，是满足它要求的一个特例：次级索引很少被修改。有一类依赖事务就是，读次级索引，再根据读到次级索引的结果，决定读/写集。

对此我持否定意见，并认为这一节的内容完全很扯...


# 4. Calvin with disk-based storage

calvin 之前的工作，都是基于内存做的。原因是传统的 traditional nondeterministic 数据库，它的保证事务最终顺序可以等价于任何一种串行顺序，而在 calvin 里面，最终顺序一定是 sequencer 选择的顺序。
并行的几个事务的执行，比如写盘花了 10ms，在传统数据库那边，(只要没有锁冲突) 会产生不同的结果，但是不管哪种都算做是对的。而 calvin 里面，只能出来一种结果，就是等这 10ms。

(简单说，它就是不能乱序写了。另外，保序和并行，又是一对天敌)

> Calvin avoids this disadvantage of determinism in the context of disk-based databases by following its guiding design principle: move as much as possible of the heavy lifting to earlier in the transactio processing pipeline, before locks are acquired.

处理方式，尽可能把重的操作，提到前面，在获取锁之前。这里面有一处优化是，sequencer 组件，收到请求后，若发现立刻执行该操作会导致卡在磁盘上，那它就故意 delay 一点点，先别转发到 scheduler 层。同时，通知 storage 组件去“预热”一下数据，把事务将要访问的数据准备到内存。这个优化可事务吞吐受到磁盘延迟的影响比较小。

这个优化实际会有两个困难：一个是需要比较精确的预测磁盘上面的延迟，这样事务发过去，数据正好准备好。另一个是，sequencer 需要精确追踪所有 storage 节点，哪些 key 是在内存里面的，这样它才能处理 data prefetch。

## 4.1 Disk I/O latency prediction

磁盘 IO 延迟其实很难预测。因为影响因素太多了。典型的：

* 物理的磁头旋转的距离
* 之前已排队的磁盘 IO 操作数量
* remote read 的情况下的网络 latency
* 存储介质挂了，failover 的情况
* 数据结构比如 B+ 树，需要多次 IO 的次数

> It is therefore impossible to predict latency perfectly, and any heuristic used will sometimes result in underestimates and sometimes in overestimates.

纯属瞎扯了，就直说无法预测，才是正经的。

这个地方估高了有问题，平白无故多出一些等待时间。估低了也有问题，请求发过去还是要 block 在磁盘那里，并且这里是在执行过程中，是挂锁等待的，导致竞争升高，会影响整体吞吐。

又是一个需要 tuning 的活。

> A more exhaustive exploration of this particular latency contention tradeoff would be an interesting avenue for future research, particularly as we experiment further with hooking Calvi up to various commercially available storage engines.

嗯，这是将来很好的一个研究方向，呵呵哒！

## 4.2 Globally tracking hot records

> .. for the sequencer to accurately determine which transactions to delay scheduling while their read sets are warmed up ...

为了让 sequencer 精确决定 transaction 应该 delay 多久，每个 node 的 sequencer 组件需要 track 整个系统当前哪些数据是在内存的。这并不是 scalable 的。

> If global lists of hot keys are not tracked at every sequencer, one solution is to delay all transactions from being scheduled until adequate time for prefetching has been allowed.

在无法知道的情况下，就无脑 delay 呗。这样会导致所有事务 latency 增加。或者是让 scheduler 来决定 delay。总之，这也并不是一个解决了的问题。

# 5. Checkpointing

calvin 有个好处是不用写物理的 REDO log。只要重放事务的输入的 history 就可以恢复到当前状态。当然，重放整个所有的 history 是很 ridiculous 的，所以有 check point。

一种 check point 模式是，replica freeze 并生成一个所有版本的 snapshot。这个只会每次一个 snapshot，并且是在 replica 上面，client 端不受影响。failover 的时候还是很有影响的，如果又要恢复，还要追数据的话。

另一种 check point 模式是 Cao etal.’s Zig-Zag algorithm [10] ，没细看。

最后一种是，如果存储引擎支持 mvcc 的情况。这种就没啥问题了。

# 6. PERFORMANCE AND SCALABILITY 

略

# 7. Related work

Calvin 的关键点就是它用的 deterministic 的方式处理事务，各个副本就不会有差异。之前有些文章也往这个方向做，但是限制是单机，单节点。一方面是吞吐会受限，另一个是单点故障的恢复。
