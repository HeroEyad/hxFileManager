package hxFileManager;

import haxe.Http;
import haxe.io.Bytes;
import sys.io.File;

class HttpManager {

    public static var hasInternet:Bool = checkInternet();

    /** Request text with optional progress callback */
    public static function requestText(url:String, ?headers:Map<String,String>, ?maxRedirects:Int = 5, ?onProgress:(downloaded:Int, total:Int) -> Void):String {
        var bytes = requestBytes(url, headers, maxRedirects, onProgress);
        return bytes.toString();
    }

    /** Request raw bytes with optional progress callback */
    public static function requestBytes(url:String, ?headers:Map<String,String>, ?maxRedirects:Int = 5, ?onProgress:(downloaded:Int, total:Int) -> Void):Bytes {
        if (maxRedirects <= 0) throw new HttpError("Too many redirects", url);

        var result:Bytes = null;
        var error:HttpError = null;
        var totalSize = 0;

        var h = new Http(url);
        h.setHeader("User-Agent", "hxFileManager");
        if (headers != null) for (k in headers.keys()) h.setHeader(k, headers.get(k));

        h.onBytes = (data:Bytes) -> {
            result = data;
            totalSize = data.length;
            if (onProgress != null) onProgress(totalSize, totalSize);
        };

        h.onError = (msg:String) -> error = new HttpError(msg, url);

        try {
            h.request(false);
        } catch (e:Dynamic) {
            throw new HttpError(Std.string(e), url);
        }

		if (error != null)
			throw error;
		var statusCode:Int = -1;
		h.onStatus = (code:Int) -> statusCode = code;
		
		h.request(false);
		
		if (isRedirect(statusCode))
		{
			var location = h.responseHeaders.get("Location");
			if (location == null)
				throw new HttpError("Redirected but missing Location header", url, statusCode, true);
			trace("[HttpManager] Redirected to: " + location);
			return requestBytes(location, headers, maxRedirects - 1, onProgress);
		}


        if (result == null) throw new HttpError("Empty response", url);

        return result;
    }

    /** Quick check if URL has bytes */
    public static function hasBytes(url:String, ?headers:Map<String,String>, ?onProgress:(Int, Int) -> Void):Bool {
        try {
            var data = requestBytes(url, headers, 5, onProgress);
            return data != null;
        } catch (e:Dynamic) {
            return false;
        }
    }

    private static function isRedirect(status:Int):Bool {
        return switch (status) {
            case 301, 302, 307, 308: true;
            default: false;
        };
    }

    public static function checkInternet():Bool {
        try {
            return requestText("https://example.com") != null;
        } catch (e:Dynamic) return false;
    }
}

private class HttpError {
    public var message:String;
    public var url:String;
    public var status:Int;
    public var redirected:Bool;

    public function new(message:String, url:String, ?status:Int = -1, ?redirected:Bool = false) {
        this.message = message;
        this.url = url;
        this.status = status;
        this.redirected = redirected;
    }

    public function toString():String {
        var parts:Array<String> = ['[HttpManager | ERROR]'];
        if (status != -1) parts.push('Status: $status');
        if (redirected) parts.push('(Redirected)');
        parts.push('URL: $url');
        parts.push('Message: $message');
        return parts.join(' | ');
    }
}
