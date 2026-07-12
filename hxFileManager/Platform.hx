package hxFileManager;

import haxe.io.Path;
import sys.FileSystem;
import hxFileManager.utils.*;

/**
 * Platform and environment helpers: elevation, app data paths, platform name.
 */
class Platform {

	#if (windows || mac || linux)
	public static final rootDir:String = Path.directory(Sys.programPath());
	#else
	public static final rootDir:String = "";
	#end

	public static final exePath:String = Sys.programPath();

	public static var isAdmin(default, null):Bool =
		#if windows   FileUtils.isUserAdmin()
		#elseif (linux || mac) Sys.command("id", ["-u"]) == 0
		#else false #end;

	/**
	 * Request administrator or elevated privileges, re-launching the process if needed. Only works on native cpp targets.
	 * @param onSuccess Optional callback on success.
	 * @param onError Optional error callback.
	 */
	public static function requestAdmin(?onSuccess:Void->Void, ?onError:String->Void):Void {
		WorkerPool.enqueue(() -> {
			try {
				#if cpp
					#if windows
					FileUtils.requestAdmin();
					#elseif linux
					try Sys.command("pkexec", [exePath]) catch (_)
						try Sys.command("gksudo", [exePath]) catch (e2:Dynamic)
							throw "Could not elevate: " + e2;
					#elseif mac
					Sys.command("osascript", ["-e", 'do shell script "$exePath" with administrator privileges']);
					#else throw "Unsupported platform"; #end
				#else
				throw "Elevation only works on native (cpp) targets";
				#end
				if (onSuccess != null) WorkerPool.mainThread(onSuccess);
			} catch (e:Dynamic) {
				if (onError != null) WorkerPool.mainThread(() -> onError(Std.string(e)));
			}
		});
	}

	/**
	 * Returns the current platform name: "Windows", "Mac", "Linux", or "unknown".
	 */
	public static function getPlatformName():String {
		#if (windows || mac || linux) return Sys.systemName();
		#else return "unknown"; #end
	}

	/**
	 * Returns the OS-appropriate application data path for the given app name, creating it if it does not exist.
	 * @param appName Application name used as the directory name.
	 */
	public static function getAppDataPath(appName:String):String {
		var base:String;
		#if windows base = Sys.getEnv("APPDATA");
		#elseif mac base = Path.join([Sys.getEnv("HOME"), "Library", "Application Support"]);
		#elseif linux base = Sys.getEnv("XDG_DATA_HOME") ?? Path.join([Sys.getEnv("HOME"), ".local", "share"]);
		#else throw "Unsupported platform"; #end
		if (base == null) throw "Could not determine AppData path";
		var appPath = Path.join([base, appName]);
		FileManager.createDirRecursive(appPath);
		return appPath;
	}
}
