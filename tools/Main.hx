package tools;

import hxFileManager.FileManager;
import hxFileManager.HttpManager;
import haxe.io.Bytes;

class Main {

	static var passed:Int = 0;
	static var failed:Int = 0;
	static var remaining:Int = 0;

	static final DIR = "_fm_test_";

	static function main() {
		FileManager.init();

		trace("=== hxFileManager Test Suite ===\n");
		trace("Platform : " + FileManager.getPlatformName());
		trace("Admin    : " + FileManager.isAdmin);
		trace("Root     : " + FileManager.rootDir + "\n");

		// --- Sync tests ---
		section("Sync Helpers");
		expect("getFileExtension",       FileManager.getFileExtension("hello.txt") == "txt");
		expect("getFileExtension upper", FileManager.getFileExtension("DATA.JSON") == "json");
		expect("getFileName",            FileManager.getFileName("a/b/file.txt") == "file.txt");
		expect("getFileNameWithoutExt",  FileManager.getFileNameWithoutExt("a/b/file.txt") == "file");
		expect("getParentDir",           FileManager.getParentDir("a/b/file.txt") == "a/b");
		expect("fileExists missing",     !FileManager.fileExists("__nope__.txt"));
		expect("folderExists missing",   !FileManager.folderExists("__nope__"));
		expect("getPlatformName",        FileManager.getPlatformName() != "unknown");

		// --- Async tests ---
		section("Async");

		// write + read
		async();
		FileManager.writeFileAsync(DIR + "rw.txt", "hello", _ -> {
			FileManager.readFileAsync(DIR + "rw.txt", content -> {
				expect("write + read", content == "hello");
				done();
			});
		});

		// append
		async();
		FileManager.writeFileAsync(DIR + "app.txt", "a", _ -> {
			FileManager.appendFileAsync(DIR + "app.txt", "b", () -> {
				FileManager.readFileAsync(DIR + "app.txt", c -> {
					expect("append", c == "ab");
					done();
				});
			});
		});

		// prepend
		async();
		FileManager.writeFileAsync(DIR + "pre.txt", "world", _ -> {
			FileManager.prependFileAsync(DIR + "pre.txt", "hello ", () -> {
				FileManager.readFileAsync(DIR + "pre.txt", c -> {
					expect("prepend", c == "hello world");
					done();
				});
			});
		});

		// lines
		async();
		FileManager.writeLinesAsync(DIR + "lines.txt", ["a", "b", "c"], () -> {
			FileManager.readLinesAsync(DIR + "lines.txt", lines -> {
				expect("write/read lines", lines.length == 3 && lines[1] == "b");
				done();
			});
		});

		// truncate
		async();
		FileManager.writeFileAsync(DIR + "trunc.txt", "stuff", _ -> {
			FileManager.truncateFileAsync(DIR + "trunc.txt", () -> {
				FileManager.readFileAsync(DIR + "trunc.txt", c -> {
					expect("truncate", c == "");
					done();
				});
			});
		});

		// safeWrite
		async();
		FileManager.writeFileAsync(DIR + "safe.txt", "old", _ -> {
			FileManager.safeWriteAsync(DIR + "safe.txt", "new", () -> {
				FileManager.readFileAsync(DIR + "safe.txt", c -> {
					expect("safeWrite content", c == "new");
					expect("safeWrite no backup", !FileManager.fileExists(DIR + "safe.txt.bak"));
					done();
				});
			});
		});

		// bytes
		async();
		var raw = Bytes.ofString("bytes test");
		FileManager.writeBytesAsync(DIR + "raw.bin", raw, _ -> {
			FileManager.readFileBytesAsync(DIR + "raw.bin", result -> {
				expect("bytes round-trip", result.compare(raw) == 0);
				done();
			});
		});

		// base64
		async();
		var b64 = haxe.crypto.Base64.encode(Bytes.ofString("b64 test"));
		FileManager.writeFileBase64Async(DIR + "b64.bin", b64, () -> {
			FileManager.readFileBase64Async(DIR + "b64.bin", result -> {
				expect("base64 round-trip", result == b64);
				done();
			});
		});

		// json
		async();
		FileManager.writeJsonAsync(DIR + "data.json", {x: 42}, _ -> {
			FileManager.readJsonAsync(DIR + "data.json", parsed -> {
				expect("json round-trip", parsed.x == 42);
				done();
			});
		});

		// patchJson
		async();
		FileManager.writeJsonAsync(DIR + "patch.json", {n: 1}, _ -> {
			FileManager.patchJsonAsync(DIR + "patch.json", d -> { d.n = d.n + 1; return d; }, () -> {
				FileManager.readJsonAsync(DIR + "patch.json", p -> {
					expect("patchJson", p.n == 2);
					done();
				});
			});
		});

		// folder create/delete
		async();
		FileManager.createFolderAsync(DIR + "sub", () -> {
			FileManager.folderExistsAsync(DIR + "sub", exists -> {
				expect("createFolder", exists);
				FileManager.deletePathAsync(DIR + "sub", () -> {
					FileManager.folderExistsAsync(DIR + "sub", gone -> {
						expect("deleteFolder", !gone);
						done();
					});
				});
			});
		});

		// copy folder
		async();
		FileManager.createFolderAsync(DIR + "src", () -> {
			FileManager.writeFileAsync(DIR + "src/f.txt", "x", _ -> {
				FileManager.copyFolderAsync(DIR + "src", DIR + "dst", () -> {
					FileManager.fileExistsAsync(DIR + "dst/f.txt", ok -> {
						expect("copyFolder", ok);
						FileManager.deletePathAsync(DIR + "src");
						FileManager.deletePathAsync(DIR + "dst");
						done();
					});
				});
			});
		});

		// listFiles
		async();
		FileManager.createFolderAsync(DIR + "ls", () -> {
			FileManager.writeFileAsync(DIR + "ls/a.txt", "a", _ -> {
				FileManager.writeFileAsync(DIR + "ls/b.txt", "b", _ -> {
					FileManager.listFilesAsync(DIR + "ls", entries -> {
						expect("listFiles", entries.length == 2);
						FileManager.deletePathAsync(DIR + "ls");
						done();
					});
				});
			});
		});

		// countFiles
		async();
		FileManager.createFolderAsync(DIR + "cnt", () -> {
			FileManager.writeFileAsync(DIR + "cnt/a.txt", "a", _ -> {
				FileManager.writeFileAsync(DIR + "cnt/b.txt", "b", _ -> {
					FileManager.countFilesAsync(DIR + "cnt", n -> {
						expect("countFiles", n == 2);
						FileManager.deletePathAsync(DIR + "cnt");
						done();
					});
				});
			});
		});

		// searchByExtension
		async();
		FileManager.createFolderAsync(DIR + "srch", () -> {
			FileManager.writeFileAsync(DIR + "srch/notes.txt", "n", _ -> {
				FileManager.writeFileAsync(DIR + "srch/image.png", "i", _ -> {
					FileManager.searchByExtensionAsync(DIR + "srch", "txt", results -> {
						expect("searchByExtension", results.length == 1);
						FileManager.deletePathAsync(DIR + "srch");
						done();
					});
				});
			});
		});

		// move file
		async();
		FileManager.writeFileAsync(DIR + "mv_src.txt", "mv", _ -> {
			FileManager.moveFileAsync(DIR + "mv_src.txt", DIR + "mv_dst.txt", () -> {
				FileManager.fileExistsAsync(DIR + "mv_dst.txt", dst -> {
					FileManager.fileExistsAsync(DIR + "mv_src.txt", src -> {
						expect("moveFile dst exists", dst);
						expect("moveFile src gone", !src);
						FileManager.deletePathAsync(DIR + "mv_dst.txt");
						done();
					});
				});
			});
		});

		// file size
		async();
		FileManager.writeFileAsync(DIR + "sz.txt", "12345", _ -> {
			FileManager.getFileSizeAsync(DIR + "sz.txt", size -> {
				expect("getFileSize", size == 5);
				FileManager.deletePathAsync(DIR + "sz.txt");
				done();
			});
		});

		// md5
		async();
		FileManager.writeFileAsync(DIR + "hash.txt", "hashme", _ -> {
			FileManager.hashFileMd5Async(DIR + "hash.txt", md5 -> {
				expect("md5 length", md5.length == 32);
				FileManager.deletePathAsync(DIR + "hash.txt");
				done();
			});
		});

		// compare files
		async();
		FileManager.writeFileAsync(DIR + "ca.txt", "same", _ -> {
			FileManager.writeFileAsync(DIR + "cb.txt", "same", _ -> {
				FileManager.compareFilesAsync(DIR + "ca.txt", DIR + "cb.txt", eq -> {
					expect("compareFiles equal", eq);
					FileManager.deletePathAsync(DIR + "ca.txt");
					FileManager.deletePathAsync(DIR + "cb.txt");
					done();
				});
			});
		});

		// batch write/read/delete
		async();
		var entries:Map<String, String> = [DIR + "b1.txt" => "one", DIR + "b2.txt" => "two"];
		FileManager.batchWriteAsync(entries, () -> {
			FileManager.batchReadAsync([DIR + "b1.txt", DIR + "b2.txt"], results -> {
				expect("batchWrite/Read", results.get(DIR + "b2.txt") == "two");
				FileManager.batchDeleteAsync([DIR + "b1.txt", DIR + "b2.txt"], () -> {
					expect("batchDelete", !FileManager.fileExists(DIR + "b1.txt"));
					done();
				});
			});
		});

		// http
		section("HttpManager");
		var online = HttpManager.checkInternet();
		expect("checkInternet", online == true || online == false);

		if (online) {
			async();
			try {
				var text = HttpManager.requestText("https://example.com");
				expect("requestText", text != null && text.length > 0);
			} catch (e:Dynamic) {
				fail("requestText: " + e);
			}
			done();

			async();
			expect("getStatusCode", HttpManager.getStatusCode("https://example.com") == 200);
			done();
		} else {
			trace("  [SKIP] no internet");
		}

		// spin until async tests settle
		while (remaining > 0) Sys.sleep(0.05);

		// cleanup
		FileManager.deletePathAsync(DIR);
	}

	static function async():Void  remaining++;
	static function done():Void   { if (--remaining <= 0) finish(); }
	static function section(n:String):Void trace('\n-- $n --');

	static function expect(label:String, ok:Bool):Void {
		if (ok) { passed++; trace('  PASS  $label'); }
		else    { failed++; trace('  FAIL  $label'); }
	}

	static function fail(label:String):Void {
		failed++;
		trace('  FAIL  $label');
	}

	static function finish():Void {
		var total = passed + failed;
		trace('\n=== Results: $passed/$total passed' + (failed > 0 ? ' (${failed} failed)' : '') + ' ===');
		FileManager.dispose();
	}
}
