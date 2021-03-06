# Go语言的抢占式调度

## 为什么抢占式调度很重要

随着Go的一步步发展，它的调度器部分的实现也越来越好了。goroutine以前是严格意义上的coroutine，也就是协程。用户负责让各个goroutine交互合作完成任务。一个goroutine只有在涉及到加锁，读写通道等操作才会触发gorouine的yield。

Go语言的垃圾回收器是stoptheworld的。如果垃圾回收器想要运行了，那么它必须先通知其它的goroutine合作停下来。这会造成较长时间的垃圾回收等待时间。我们考虑一种很极端的情况，其它的goroutine都停下来了，除了有一个没有停，那么垃圾回收就会一直等待。

抢占式调度可以解决这种问题，在抢占式情况下，不停goroutine是否合作，它都会被yield。

## 初步实现

引入抢占式调度，会对最初的设计产生比较大的影响，因此到目前(1.2 alpha)为止Go还只是引入了一些很初级的抢占，并没有像操作系统调度那么复杂，没有对goroutine分时间片，设置优先级等。

只有长时间阻塞于系统调用，或者运行了较长时间才会被抢占。runtime会在后台有一个检测线程，它会检测这些情况，并通知goroutine执行调度。

目前并没有直接在后台的检测线程中做处理调度器相关逻辑，只是相当于给goroutine加了一个“标记”，然后在它进入函数时才会触发调度。这么做应该是出于对现有代码的修改最小的考虑。

## sysmon

前面讲Go程序的初始化过程中有提到过，runtime开了一条后台线程，运行一个sysmon函数。这个函数会周期性地做epoll操作，同时它还会检测每个P是否运行了较长时间。

如果检测到某个P状态处于Psyscall超过了一个sysmon的时间周期(20us)，并且还有其它可运行的任务，则切换P。

如果检测到某个P的状态为Prunning，并且它已经运行了超过10ms，则会将P的当前的G的stackguard设置为StackPreempt。这个操作其实是相当于加上一个标记，通知这个G在合适时机进行调度。

目前这里只是尽最大努力送达，但并不保证收到消息的goroutine一定会执行调度让出运行权。

## morestack的修改

前面说的，将stackguard设置为StackPreempt实际上是一个比较trick的代码。我们知道Go使用的是分段栈，它会在每个函数入口处比较当前的栈寄存器值和stackguard值来决定是否触发morestack函数。

将stackguard设置为StackPreempt作用是进入函数时必定触发morestack，然后在morestack中再引发调度。

看一下StackPreempt的定义，它是大于任何实际的栈寄存器的值的：

	// 0xfffffade in hex.
	#define StackPreempt ((uint64)-1314)

然后在morestack中加了一小段代码，如果发现stackguard为StackPreempt，则相当于调用runtime.Gosched。

所以，到目前为止Go的抢占式调度还是很初级的，比如一个goroutine运行了很久，但是它并没有调用另一个函数，则它不会被抢占。当然，一个运行很久却不调用函数的代码并不是多数情况。
