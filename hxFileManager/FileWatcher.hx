package hxFileManager;

import haxe.io.Path;
import sys.FileSystem;
import sys.thread.Thread;
import sys.thread.Mutex;

/**
 * Watches a file or folder for changes using mtime polling.
 * Each watcher runs on its own dedicated thread so polling never starves the WorkerPool.
 * Create via FileWatcher.folder() or FileWatcher.file(), stop via stop().
 */
class FileWatcher {

	final path:String;
	final onChange:Void->Void;
	final intervalMs:Int;
	final isFolder:Bool;
	final mutex:Mutex = new Mutex();

	var alive:Bool = true;

	function new(path:String, onChange:Void->Void, intervalMs:Int, isFolder:Bool) {
		this.path = path;
		this.onChange = onChange;
		this.intervalMs = intervalMs;
		this.isFolder = isFolder;
		Thread.create(loop);
	}

	/**
	 * Watch a folder for changes.
	 * @param path Folder path to watch.
	 * @param onChange Callback invoked on the main thread when a change is detected.
	 * @param intervalMs Polling interval in milliseconds (default 1000).
	 */
	public static inline function folder(path:String, onChange:Void->Void, intervalMs:Int = 1000):FileWatcher
		return new FileWatcher(path, onChange, intervalMs, true);

	/**
	 * Watch a single file for modifications.
	 * @param path File path to watch.
	 * @param onChange Callback invoked on the main thread when the file changes.
	 * @param intervalMs Polling interval in milliseconds (default 500).
	 */
	public static inline function file(path:String, onChange:Void->Void, intervalMs:Int = 500):FileWatcher
		return new FileWatcher(path, onChange, intervalMs, false);

	/**
	 * Stop the watcher. The polling thread exits after its current sleep.
	 */
	public function stop():Void {
		mutex.acquire();
		alive = false;
		mutex.release();
	}

	function isAlive():Bool {
		mutex.acquire();
		var a = alive;
		mutex.release();
		return a;
	}

	function loop():Void {
		var prev = snapshot();
		while (isAlive()) {
			Sys.sleep(intervalMs / 1000.0);
			if (!isAlive()) return;
			var now = snapshot();
			if (now != prev) {
				prev = now;
				WorkerPool.mainThread(onChange);
			}
		}
	}

	function snapshot():Float {
		if (isFolder) {
			var hash:Float = 0;
			if (!FileSystem.exists(path) || !FileSystem.isDirectory(path)) return 0;
			for (item in FileSystem.readDirectory(path)) {
				var full = Path.join([path, item]);
				if (!FileSystem.isDirectory(full)) hash += FileSystem.stat(full).mtime.getTime();
			}
			return hash;
		}
		return (FileSystem.exists(path) && !FileSystem.isDirectory(path)) ? FileSystem.stat(path).mtime.getTime() : 0;
	}
}
