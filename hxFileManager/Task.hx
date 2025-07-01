package hxFileManager;

class Task {
	public final run:Void->Void;

	public function new(run:Void->Void) {
		this.run = run;
	}
}
