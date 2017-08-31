// D import file generated from 'src/core/sync/semaphore.d'
module core.sync.semaphore;
public import core.sync.exception;
public import core.time;
version (OSX)
{
	version = Darwin;
}
else
{
	version (iOS)
	{
		version = Darwin;
	}
	else
	{
		version (TVOS)
		{
			version = Darwin;
		}
		else
		{
			version (WatchOS)
			{
				version = Darwin;
			}
		}
	}
}
version (Windows)
{
	private import core.sys.windows.windows;
}
else
{
	version (Darwin)
	{
		private import core.sync.config;
		private import core.stdc.errno;
		private import core.sys.posix.time;
		private import core.sys.darwin.mach.semaphore;
	}
	else
	{
		version (Posix)
		{
			private import core.sync.config;
			private import core.stdc.errno;
			private import core.sys.posix.pthread;
			private import core.sys.posix.semaphore;
		}
		else
		{
			static assert(false, "Platform not supported");
		}
	}
}
class Semaphore
{
	this(uint count = 0)
	{
		version (Windows)
		{
			m_hndl = CreateSemaphoreA(null, count, (int).max, null);
			if (m_hndl == m_hndl.init)
				throw new SyncError("Unable to create semaphore");
		}
		else
		{
			version (Darwin)
			{
				auto rc = semaphore_create(mach_task_self(), &m_hndl, SYNC_POLICY_FIFO, count);
				if (rc)
					throw new SyncError("Unable to create semaphore");
			}
			else
			{
				version (Posix)
				{
					int rc = sem_init(&m_hndl, 0, count);
					if (rc)
						throw new SyncError("Unable to create semaphore");
				}

			}
		}
	}
	~this();
	void wait();
	bool wait(Duration period);
	void notify();
	bool tryWait();
	private version (Windows)
	{
		HANDLE m_hndl;
	}
	else
	{
		version (Darwin)
		{
			semaphore_t m_hndl;
		}
		else
		{
			version (Posix)
			{
				sem_t m_hndl;
			}
		}
	}
}
version (unittest)
{
	import core.thread;
	import core.atomic;
	void testWait();
	void testWaitTimeout();
}
