package hxFileManager;

import haxe.Timer;
import sys.thread.Thread;
import sys.thread.Deque;

private class Task {
	public final fn:Void->Void;
	public function new(fn:Void->Void) this.fn = fn;
	public inline function run():Void fn();
}

/**
 * Shared worker-thread pool used by FileManager, FileWatcher and anything else
 * that wants to run blocking work off the main thread.
 */
class WorkerPool {

	static final queue:Deque<Task> = new Deque();
	static var workers:Array<Thread> = [];

	public static var running(default, null):Bool = false;

	/**
	 * Initialise the pool. Must be called before any async method. Safe to call multiple times.
	 * @param numThreads Number of worker threads (default 4).
	 */
	public static function init(numThreads:Int = 4):Void {
		if (running) return;
		running = true;
		for (_ in 0...numThreads) workers.push(Thread.create(workerLoop));
	}

	/**
	 * Drain the queue and stop all worker threads.
	 */
	public static function dispose():Void {
		if (!running) return;
		running = false;
		for (_ in workers) queue.add(new Task(() -> {}));
		workers = [];
	}

	static function workerLoop():Void {
		while (running) {
			var task = queue.pop(true);
			if (task == null || !running) break;
			try task.run() catch (e) trace("WorkerPool error: " + e);
		}
	}

	/**
	 * Enqueue arbitrary work onto the pool.
	 * @param fn Function to execute on a worker thread.
	 */
	public static inline function enqueue(fn:Void->Void):Void {
		#if debug
		if (!running) throw "WorkerPool not initialised — call WorkerPool.init() (or FileManager.init()) first";
		#end
		queue.add(new Task(fn));
	}

	/**
	 * Schedule a function to run on the main thread's event loop.
	 * @param fn Function to run.
	 */
	public static inline function mainThread(fn:Void->Void):Void
		Timer.delay(fn, 0);
}
