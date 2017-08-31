// D import file generated from 'src/core/sync/mutex.d'
module core.sync.mutex;
public import core.sync.exception;
version (Windows)
{
	private import core.sys.windows.windows;
}
else
{
	version (Posix)
	{
		private import core.sys.posix.pthread;
	}
	else
	{
		static assert(false, "Platform not supported");
	}
}
class Mutex : Object.Monitor
{
	nothrow @nogc @trusted this()
	{
		this(true);
	}
	shared nothrow @nogc @trusted this()
	{
		this(true);
	}
	private nothrow @nogc @trusted this(this Q)(bool _unused_) if (is(Q == Mutex) || is(Q == shared(Mutex)))
	{
		version (Windows)
		{
			InitializeCriticalSection(cast(CRITICAL_SECTION*)&m_hndl);
		}
		else
		{
			version (Posix)
			{
				import core.internal.abort : abort;
				pthread_mutexattr_t attr = void;
				!pthread_mutexattr_init(&attr) || abort("Error: pthread_mutexattr_init failed.");
				scope(exit) !pthread_mutexattr_destroy(&attr) || abort("Error: pthread_mutexattr_destroy failed.");
				!pthread_mutexattr_settype(&attr, PTHREAD_MUTEX_RECURSIVE) || abort("Error: pthread_mutexattr_settype failed.");
				!pthread_mutex_init(cast(pthread_mutex_t*)&m_hndl, &attr) || abort("Error: pthread_mutex_init failed.");
			}

		}
		m_proxy.link = this;
		this.__monitor = cast(void*)&m_proxy;
	}
	nothrow @nogc @trusted this(Object obj)
	{
		this(obj, true);
	}
	shared nothrow @nogc @trusted this(Object obj)
	{
		this(obj, true);
	}
	private nothrow @nogc @trusted this(this Q)(Object obj, bool _unused_) if (is(Q == Mutex) || is(Q == shared(Mutex)))
	in
	{
		assert(obj !is null, "The provided object must not be null.");
		assert(obj.__monitor is null, "The provided object has a monitor already set!");
	}
	body
	{
		this();
		obj.__monitor = cast(void*)&m_proxy;
	}
	@trusted @nogc ~this();
	@trusted void lock();
	shared @trusted void lock();
	final nothrow @nogc @trusted void lock_nothrow(this Q)() if (is(Q == Mutex) || is(Q == shared(Mutex)))
	{
		version (Windows)
		{
			EnterCriticalSection(&m_hndl);
		}
		else
		{
			version (Posix)
			{
				if (pthread_mutex_lock(&m_hndl) == 0)
					return ;
				SyncError syncErr = cast(SyncError)cast(void*)typeid(SyncError).initializer;
				syncErr.msg = "Unable to lock mutex.";
				throw syncErr;
			}

		}
	}
	@trusted void unlock();
	shared @trusted void unlock();
	final nothrow @nogc @trusted void unlock_nothrow(this Q)() if (is(Q == Mutex) || is(Q == shared(Mutex)))
	{
		version (Windows)
		{
			LeaveCriticalSection(&m_hndl);
		}
		else
		{
			version (Posix)
			{
				if (pthread_mutex_unlock(&m_hndl) == 0)
					return ;
				SyncError syncErr = cast(SyncError)cast(void*)typeid(SyncError).initializer;
				syncErr.msg = "Unable to unlock mutex.";
				throw syncErr;
			}

		}
	}
	@trusted bool tryLock();
	shared @trusted bool tryLock();
	final nothrow @nogc @trusted bool tryLock_nothrow(this Q)() if (is(Q == Mutex) || is(Q == shared(Mutex)))
	{
		version (Windows)
		{
			return TryEnterCriticalSection(&m_hndl) != 0;
		}
		else
		{
			version (Posix)
			{
				return pthread_mutex_trylock(&m_hndl) == 0;
			}

		}
	}
	private 
	{
		version (Windows)
		{
			CRITICAL_SECTION m_hndl;
		}
		else
		{
			version (Posix)
			{
				pthread_mutex_t m_hndl;
			}
		}
		struct MonitorProxy
		{
			Object.Monitor link;
		}
		MonitorProxy m_proxy;
		package version (Posix)
		{
			pthread_mutex_t* handleAddr();
		}
	}
}
