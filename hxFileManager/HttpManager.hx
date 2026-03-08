package hxFileManager;

import haxe.Http;
import haxe.Json;
import haxe.io.Bytes;
import haxe.Timer;
import sys.io.File;

class HttpManager {

	public static var hasInternet:Bool = checkInternet();
	public static var defaultUserAgent:String = "hxFileManager";
	public static var defaultTimeout:Int = 10;

	/** Request text from a URL. @param url Target URL. @param headers Optional headers. @param maxRedirects Max redirects to follow (default 5). @param onProgress Optional progress callback (downloaded, total). */
	public static function requestText(url:String, ?headers:Map<String, String>, maxRedirects:Int = 5, ?onProgress:(Int, Int)->Void):String
		return requestBytes(url, headers, maxRedirects, onProgress).toString();

	/** Request raw bytes from a URL. @param url Target URL. @param headers Optional headers. @param maxRedirects Max redirects to follow (default 5). @param onProgress Optional progress callback (downloaded, total). */
	public static function requestBytes(url:String, ?headers:Map<String, String>, maxRedirects:Int = 5, ?onProgress:(Int, Int)->Void):Bytes {
		if (maxRedirects < 0) throw new HttpError("Too many redirects", url);

		var result:Bytes = null;
		var error:HttpError = null;
		var statusCode:Int = -1;

		var h = buildRequest(url, headers);

		h.onBytes = (data:Bytes) -> {
			result = data;
			if (onProgress != null) onProgress(data.length, data.length);
		};
		h.onError = (msg:String) -> error = new HttpError(msg, url);
		h.onStatus = (code:Int) -> statusCode = code;

		try h.request(false)
		catch (e:Dynamic) throw new HttpError(Std.string(e), url);

		if (error != null) throw error;

		if (isRedirect(statusCode)) {
			var location = h.responseHeaders != null ? h.responseHeaders.get("Location") : null;
			if (location == null) throw new HttpError("Redirect missing Location header", url, statusCode, true);
			trace("[HttpManager] Redirect -> " + location);
			return requestBytes(location, headers, maxRedirects - 1, onProgress);
		}

		if (result == null) throw new HttpError("Empty response", url, statusCode);
		return result;
	}

	/** POST JSON data to a URL. @param url Target URL. @param data Object to serialise as JSON body. @param headers Optional extra headers. @param onSuccess Optional callback with response text. @param onError Optional callback with error message. */
	public static function postJson(url:String, data:Dynamic, ?headers:Map<String, String>, ?onSuccess:String->Void, ?onError:String->Void):Void {
		var h = buildRequest(url, headers);
		h.setHeader("Content-Type", "application/json");
		h.setPostData(Json.stringify(data));
		h.onData = (d:String) -> if (onSuccess != null) onSuccess(d);
		h.onError = (msg:String) -> if (onError != null) onError(msg);
		try h.request(true)
		catch (e:Dynamic) if (onError != null) onError(Std.string(e));
	}

	/** POST form-encoded key-value pairs to a URL. @param url Target URL. @param fields Map of field name to value. @param headers Optional extra headers. @param onSuccess Optional callback with response text. @param onError Optional callback with error message. */
	public static function postForm(url:String, fields:Map<String, String>, ?headers:Map<String, String>, ?onSuccess:String->Void, ?onError:String->Void):Void {
		var h = buildRequest(url, headers);
		h.setHeader("Content-Type", "application/x-www-form-urlencoded");
		var parts:Array<String> = [];
		for (k => v in fields) parts.push(StringTools.urlEncode(k) + "=" + StringTools.urlEncode(v));
		h.setPostData(parts.join("&"));
		h.onData = (d:String) -> if (onSuccess != null) onSuccess(d);
		h.onError = (msg:String) -> if (onError != null) onError(msg);
		try h.request(true)
		catch (e:Dynamic) if (onError != null) onError(Std.string(e));
	}

	/** Send a DELETE request. @param url Target URL. @param headers Optional headers. @param onSuccess Optional callback with response text. @param onError Optional callback with error message. */
	public static function delete(url:String, ?headers:Map<String, String>, ?onSuccess:String->Void, ?onError:String->Void):Void {
		var h = buildRequest(url, headers);
		h.setHeader("X-HTTP-Method-Override", "DELETE");
		h.onData = (d:String) -> if (onSuccess != null) onSuccess(d);
		h.onError = (msg:String) -> if (onError != null) onError(msg);
		try h.request(false)
		catch (e:Dynamic) if (onError != null) onError(Std.string(e));
	}

	/** Send a PUT request with a JSON body. @param url Target URL. @param data Object to serialise as JSON body. @param headers Optional extra headers. @param onSuccess Optional callback with response text. @param onError Optional callback with error message. */
	public static function putJson(url:String, data:Dynamic, ?headers:Map<String, String>, ?onSuccess:String->Void, ?onError:String->Void):Void {
		var h = buildRequest(url, headers);
		h.setHeader("Content-Type", "application/json");
		h.setHeader("X-HTTP-Method-Override", "PUT");
		h.setPostData(Json.stringify(data));
		h.onData = (d:String) -> if (onSuccess != null) onSuccess(d);
		h.onError = (msg:String) -> if (onError != null) onError(msg);
		try h.request(true)
		catch (e:Dynamic) if (onError != null) onError(Std.string(e));
	}

	/** Send a PATCH request with a JSON body. @param url Target URL. @param data Object to serialise as JSON body. @param headers Optional extra headers. @param onSuccess Optional callback with response text. @param onError Optional callback with error message. */
	public static function patchJson(url:String, data:Dynamic, ?headers:Map<String, String>, ?onSuccess:String->Void, ?onError:String->Void):Void {
		var h = buildRequest(url, headers);
		h.setHeader("Content-Type", "application/json");
		h.setHeader("X-HTTP-Method-Override", "PATCH");
		h.setPostData(Json.stringify(data));
		h.onData = (d:String) -> if (onSuccess != null) onSuccess(d);
		h.onError = (msg:String) -> if (onError != null) onError(msg);
		try h.request(true)
		catch (e:Dynamic) if (onError != null) onError(Std.string(e));
	}

	/** Fetch a URL and parse the response as JSON. @param url Target URL. @param headers Optional headers. @param onSuccess Callback with parsed JSON. @param onError Optional error callback. */
	public static function getJson(url:String, ?headers:Map<String, String>, onSuccess:Dynamic->Void, ?onError:String->Void):Void {
		var h = buildRequest(url, headers);
		h.setHeader("Accept", "application/json");
		h.onData = (d:String) -> {
			try onSuccess(Json.parse(d))
			catch (e:Dynamic) if (onError != null) onError("JSON parse error: " + Std.string(e));
		};
		h.onError = (msg:String) -> if (onError != null) onError(msg);
		try h.request(false)
		catch (e:Dynamic) if (onError != null) onError(Std.string(e));
	}

	/** Download a URL to a local file path. @param url Remote URL. @param savePath Local destination path. @param headers Optional headers. @param onProgress Optional progress callback (downloaded, total). @param onDone Optional completion callback. @param onError Optional error callback. */
	public static function downloadTo(url:String, savePath:String, ?headers:Map<String, String>, ?onProgress:(Int, Int)->Void, ?onDone:Void->Void, ?onError:String->Void):Void {
		try {
			var bytes = requestBytes(url, headers, 5, onProgress);
			sys.io.File.saveBytes(savePath, bytes);
			if (onDone != null) onDone();
		} catch (e:Dynamic) {
			if (onError != null) onError(Std.string(e));
		}
	}

	/** Check if a URL returns any bytes without throwing. @param url Target URL. @param headers Optional headers. */
	public static function hasBytes(url:String, ?headers:Map<String, String>):Bool {
		try return requestBytes(url, headers) != null
		catch (_) return false;
	}

	/** Return the HTTP status code for a URL without downloading the body. @param url Target URL. @param headers Optional headers. */
	public static function getStatusCode(url:String, ?headers:Map<String, String>):Int {
		var code = -1;
		var h = buildRequest(url, headers);
		h.onStatus = (c:Int) -> code = c;
		h.onBytes = (_) -> {};
		h.onError = (_) -> {};
		try h.request(false) catch (_) {}
		return code;
	}

	/** Return all response headers for a URL. @param url Target URL. @param headers Optional request headers. */
	public static function getResponseHeaders(url:String, ?headers:Map<String, String>):Map<String, String> {
		var h = buildRequest(url, headers);
		h.onBytes = (_) -> {};
		h.onError = (_) -> {};
		try h.request(false) catch (_) {}
		return h.responseHeaders ?? new Map();
	}

	/** Retry a request up to maxAttempts times with an optional delay between attempts. @param url Target URL. @param maxAttempts Max number of attempts (default 3). @param delayMs Milliseconds to wait between attempts (default 500). @param headers Optional headers. */
	public static function requestWithRetry(url:String, maxAttempts:Int = 3, delayMs:Int = 500, ?headers:Map<String, String>):Bytes {
		var lastErr:Dynamic = null;
		for (i in 0...maxAttempts) {
			try return requestBytes(url, headers)
			catch (e:Dynamic) {
				lastErr = e;
				if (i < maxAttempts - 1) Sys.sleep(delayMs / 1000.0);
			}
		}
		throw lastErr;
	}

	/** Check internet connectivity by hitting a lightweight URL. Updates hasInternet. */
	public static function checkInternet():Bool {
		try {
			hasInternet = requestText("https://example.com") != null;
		} catch (_) {
			hasInternet = false;
		}
		return hasInternet;
	}

	/** Check internet connectivity asynchronously via a timer-based approach. @param onResult Callback with true if internet is reachable. */
	public static function checkInternetAsync(onResult:Bool->Void):Void {
		Timer.delay(() -> onResult(checkInternet()), 0);
	}

	static function buildRequest(url:String, ?headers:Map<String, String>):Http {
		var h = new Http(url);
		h.setHeader("User-Agent", defaultUserAgent);
		if (headers != null) for (k => v in headers) h.setHeader(k, v);
		return h;
	}

	static function isRedirect(status:Int):Bool {
		return status == 301 || status == 302 || status == 307 || status == 308;
	}
}

class HttpError {
	public var message:String;
	public var url:String;
	public var status:Int;
	public var redirected:Bool;

	public function new(message:String, url:String, status:Int = -1, redirected:Bool = false) {
		this.message = message;
		this.url = url;
		this.status = status;
		this.redirected = redirected;
	}

	public function toString():String {
		var parts = ["[HttpManager | ERROR]"];
		if (status != -1) parts.push('Status: $status');
		if (redirected) parts.push("(Redirected)");
		parts.push('URL: $url');
		parts.push('Message: $message');
		return parts.join(" | ");
	}
}
