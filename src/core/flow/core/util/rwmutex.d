module flow.core.util.rwmutex;

private import core.sync.mutex;
private import flow.core.util;

/// this readwrite mutex is meant only for systems reusing threads
class RwMutex : Mutex {
	private import core.thread;

	private Mutex[Thread] _reader;
	@property Mutex reader() {
		auto t = Thread.getThis;

		if(t !in this._reader)
			this._reader[t] = new Mutex;
		return this._reader[t];
	}

	this() { }

	void dispose() {
		synchronized(this) {
			this.lockReader();
			foreach(t, m; this._reader)
				m.destroy;
		}

		this.destroy;
	}

	override @trusted void lock() {
		this.lockReader();
		super.lock();
	}

	override @trusted void lock() shared {
		this.lockReader();
		super.lock();
	}

	override @trusted void unlock() {
		this.unlockReader();
		super.unlock();
	}

	override @trusted void unlock() shared {
		this.unlockReader();
		super.unlock();
	}

	override bool tryLock() @trusted {
		this.lockReader();
		if(!super.tryLock()) {
			this.unlockReader();
			return false;
		} else return true;

	}

	override shared bool tryLock() @trusted {
		this.lockReader();
		if(!super.tryLock()) {
			this.unlockReader();
			return false;
		} else return true;
	}

	final void lockReader() @trusted {
		foreach(t, m; this._reader)
		 	// for its own thread it has to leave it as it is
			if(t != Thread.getThis)
				m.lock();
	}

	final shared void lockReader() @trusted {
		foreach(t, m; this._reader)
		 	// for its own thread it has to leave it as it is
			if(t != Thread.getThis)
				m.lock();
	}

	final void unlockReader() @trusted {
		foreach(t, m; this._reader)
		 	// for its own thread it has to leave it as it is
			if(t != Thread.getThis)
				m.unlock();
	}

	final shared void unlockReader() @trusted {
		foreach(t, m; this._reader)
		 	// for its own thread it has to leave it as it is
			if(t != Thread.getThis)
				m.unlock();
	}
}

// this test will loop forever if it fails
unittest { test.header("TEST util.rwmutex");

	// lock upgrade
    RwMutex m = new RwMutex;
	synchronized(m.reader) {
		synchronized(m) {
			assert(true, "couldn't set write lock");
		}
	}

    // TODO tests with taskpool

test.footer(); }