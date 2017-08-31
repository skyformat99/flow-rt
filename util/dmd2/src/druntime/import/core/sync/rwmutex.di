// D import file generated from 'src/core/sync/rwmutex.d'
module core.sync.rwmutex;
public import core.sync.exception;
private import core.sync.condition;
private import core.sync.mutex;
private import core.memory;
version (Posix)
{
	private import core.sys.posix.pthread;
}
class ReadWriteMutex
{
	enum Policy 
	{
		PREFER_READERS,
		PREFER_WRITERS,
	}
	this(Policy policy = Policy.PREFER_WRITERS)
	{
		m_commonMutex = new Mutex;
		if (!m_commonMutex)
			throw new SyncError("Unable to initialize mutex");
		m_readerQueue = new Condition(m_commonMutex);
		if (!m_readerQueue)
			throw new SyncError("Unable to initialize mutex");
		m_writerQueue = new Condition(m_commonMutex);
		if (!m_writerQueue)
			throw new SyncError("Unable to initialize mutex");
		m_policy = policy;
		m_reader = new Reader;
		m_writer = new Writer;
	}
	@property Policy policy();
	@property Reader reader();
	@property Writer writer();
	class Reader : Object.Monitor
	{
		this()
		{
			m_proxy.link = this;
			this.__monitor = &m_proxy;
		}
		@trusted void lock();
		@trusted void unlock();
		bool tryLock();
		private 
		{
			@property bool shouldQueueReader();
			struct MonitorProxy
			{
				Object.Monitor link;
			}
			MonitorProxy m_proxy;
		}
	}
	class Writer : Object.Monitor
	{
		this()
		{
			m_proxy.link = this;
			this.__monitor = &m_proxy;
		}
		@trusted void lock();
		@trusted void unlock();
		bool tryLock();
		private 
		{
			@property bool shouldQueueWriter();
			struct MonitorProxy
			{
				Object.Monitor link;
			}
			MonitorProxy m_proxy;
		}
	}
	private 
	{
		Policy m_policy;
		Reader m_reader;
		Writer m_writer;
		Mutex m_commonMutex;
		Condition m_readerQueue;
		Condition m_writerQueue;
		int m_numQueuedReaders;
		int m_numActiveReaders;
		int m_numQueuedWriters;
		int m_numActiveWriters;
	}
}
