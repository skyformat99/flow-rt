module __flow.lib.opencl;

import std.uuid, std.conv;

import derelict.opencl.cl, derelict.opencl.types;

// C example https://www.fixstars.com/en/opencl/book/OpenCLProgrammingBook/first-opencl-program/
// C example https://developer.apple.com/library/content/samplesource/OpenCL_Hello_World_Example/Listings/hello_c.html
// D example https://github.com/dmakarov/clop/blob/master/clop/rt/clid/platform.d

class ClException : Exception
{
    static ClException get(string func, cl_uint errno)
    {
        import std.conv;

        return new ClException(func, errno.to!uint); 
    }

    private uint _errno;
    @property uint errno(){return this._errno;}

    private this(string func, uint errno)
    {
        this._errno = errno;

        super("\"" ~ func ~ "\" threw " ~ errno.to!string);
    }
}

class ClDevice
{
    private UUID _id; @property UUID id(){return this._id;}
    private ClPlatform _platform;
    @property ClPlatform platform(){return this._platform;}

    private cl_device_id _clId;

    private string _name; @property string name(){return this._name;}
    private string _vendor; @property string vendor(){return this._vendor;}
    private string _version; @property string version_(){return this._version;}
    private string _profile; @property string profile(){return this._profile;}
    private string[] _extensions; @property string[] extensions(){return this._extensions;}

    this(ClPlatform platform, cl_device_id clId)
    {
        this._id = randomUUID;
        this._platform = platform;
        this._clId = clId;

        this.loadProperties();
    }

    private void buildProgram(ClProgram program)
    {
        cl_int status = clBuildProgram(program._clId, 1, &this._clId, null, null, null);
        if(status != CL_SUCCESS)
            throw(ClException.get("clBuildProgram", status));
    }

    private void loadProperties()
    {
        import std.array;
        this._name = this.getInfo!string(CL_DEVICE_NAME);
        this._vendor = this.getInfo!string(CL_DEVICE_VENDOR);
        this._version = this.getInfo!string(CL_DEVICE_VERSION);
        this._profile = this.getInfo!string(CL_DEVICE_PROFILE);
        this._extensions = this.getInfo!string(CL_DEVICE_EXTENSIONS).split(" ");
    }

    private T getInfo(T)(cl_uint param) if(is(T == string))
    {
        cl_ulong length;
        cl_int status = clGetDeviceInfo(this._clId, param, cast(ulong)0, null, &length);

        if(status != CL_SUCCESS)
            throw(ClException.get("clGetDeviceInfo", status));

        cl_char[] val = new cl_char[length];
        status = clGetPlatformInfo(this._clId, param, length, val.ptr, null);

        if(status != CL_SUCCESS)
            throw(ClException.get("clGetPlatformInfo", status));
        
        return val.to!string;
    }
}

class ClPlatform
{
    private UUID _id; @property UUID id(){return this._id;}
    private ClContext _context;
    private cl_platform_id _clId;
    private ClDevice[] _devices;
    @property ClDevice[] devices(){return this._devices;}

    private string _name; @property string name(){return this._name;}
    private string _vendor; @property string vendor(){return this._vendor;}
    private string _version; @property string version_(){return this._version;}
    private string _profile; @property string profile(){return this._profile;}
    
    this(ClContext context, cl_platform_id clId)
    {
        this._context = context;
        this._id = randomUUID;
        this._clId = clId;

        this.loadProperties();
        this.loadDevices();
    }

    private void loadProperties()
    {
        this._name = this.getInfo!string(CL_PLATFORM_NAME);
        this._vendor = this.getInfo!string(CL_PLATFORM_VENDOR);
        this._version = this.getInfo!string(CL_PLATFORM_VERSION);
        this._profile = this.getInfo!string(CL_PLATFORM_PROFILE);
    }

    private T getInfo(T)(cl_uint param) if(is(T == string))
    {
        cl_ulong length;
        cl_int status = clGetPlatformInfo(this._clId, param, cast(ulong)0, null, &length);

        if(status != CL_SUCCESS)
            throw(ClException.get("clGetPlatformInfo", status));
            
        cl_char[] val = new cl_char[length];
        status = clGetPlatformInfo(this._clId, param, length, val.ptr, null);

        if(status != CL_SUCCESS)
            throw(ClException.get("clGetPlatformInfo", status));
        
        return val.to!string;
    }

    private void loadDevices()
    {
        cl_uint numDevices;
        cl_int status = clGetDeviceIDs(this._clId, CL_DEVICE_TYPE_ALL, 0, null, &numDevices);

        if(status == CL_SUCCESS)
        {
            cl_device_id[] devices = new cl_device_id[numDevices];
            status = clGetDeviceIDs(this._clId, CL_DEVICE_TYPE_ALL, numDevices, devices.ptr, null);

            if(status == CL_SUCCESS)
            {
                foreach(d; devices)
                    try
                    {
                        import std.algorithm.searching;
                        auto device = new ClDevice(this, d);

                        auto supportsAllExt = true;
                        foreach(e; this._context._requiredExtensions)
                            if(!device.extensions.any!(de => de == e))
                            {supportsAllExt = false; break;}

                        if(supportsAllExt)
                            _devices ~= device;
                    }catch(Exception exc){}
            }
        }
    }
}

class ClQueue
{
    private cl_command_queue _clId;
    private ClContext _context;

    this(ClContext context)
    {
        this._context = context;

        this.createClQueue();
    }

    private void createClQueue()
    {
        cl_int status = 0;
        this._clId = clCreateCommandQueue(this._context._clId,  this._context.device._clId, 0, &status);

        if(status != CL_SUCCESS)
            throw(ClException.get("clCreateCommandQueue", status));
    }

    void release()
    {
        clReleaseCommandQueue(this._clId);
    }
}

class ClKernel
{
    private cl_kernel _clId;
    private ClProgram _program;

    private string _name; @property string name(){return this._name;}

    this(ClProgram program, string name)
    {
        this._name = name;
        this.createKernel();
    }

    private void createKernel()
    {
        cl_int status = 0;
        this._clId = clCreateKernel(this._program._clId,  cast(char*)this.name, &status);

        if(status != CL_SUCCESS)
            throw(ClException.get("clCreateKernel", status));
    }

    void release()
    {
        clReleaseKernel(this._clId);
    }
}

class ClProgram
{
    private cl_command_queue _clId;
    private ClContext _context;

    private string _source; @property string source(){return this._source;}
    private string[] _kernelNames;
    private ClKernel[] _kernel; @property ClKernel[] kernel(){return this._kernel;}

    this(ClContext context, string source, string[] kernelNames)
    {
        this._context = context;
        this._source = source;
        this._kernelNames = kernelNames;

        this.createClProgram();
    }

    private void createClProgram()
    {
        cl_int status = 0;
        char *[] program = [cast(char *)this.source.ptr];
        auto length = this.source.length;
        this._clId = clCreateProgramWithSource(this._context._clId, cast(uint)1, program.ptr, &length, &status);

        if(status != CL_SUCCESS)
            throw(ClException.get("clCreateProgramWithSource", status));

        this._context.device.buildProgram(this);

        this.loadKernel();
    }

    private void loadKernel()
    {
        foreach(k; this._kernelNames)
            this._kernel ~= new ClKernel(this, k);
    }

    void release()
    {
        clReleaseProgram(this._clId);
    }
}

enum ClContextState
{
    Initialized,
    Failed,
    Started,
    Stopped
}

class ClContext
{
    private UUID _id; @property UUID id(){return this._id;}
    private cl_context _clId;
    
    private ClContextState _state;
    @property ClContextState state(){return this._state;}

    private ClPlatform[] _platforms;
    @property ClPlatform[] platforms(){return _platforms;}

    private ClDevice _device; @property ClDevice device(){return this._device;}

    private ClProgram[UUID] _programs;
    private ClQueue _queue; @property ClQueue queue(){return this._queue;}

    private string[] _requiredExtensions;

    this(UUID id, string[] requiredExtensions)
    {
        this._id = id;
        this._requiredExtensions = requiredExtensions;

        this.loadPlatforms();

        this._state = ClContextState.Initialized;
    }

    private void loadPlatforms()
    {
        cl_uint numPlatforms;
        cl_int status = clGetPlatformIDs(0, null, &numPlatforms);

        if(status == CL_SUCCESS)
        {
            cl_platform_id[] platforms = new cl_platform_id[numPlatforms];
            status = clGetPlatformIDs(numPlatforms, platforms.ptr, null);

            if(status == CL_SUCCESS)
            {
                foreach(p; platforms)
                        try{_platforms ~= new ClPlatform(this, p);}catch(Exception exc){}
            }
        }
    }

    void create(UUID deviceId)
    {
        foreach(p; this.platforms)
            foreach(d; p.devices)
                if(d.id == deviceId)
                {
                    this._device = d;
                    break;
                }

        this.createClContext();
        this._queue = new ClQueue(this);

        this._state = ClContextState.Started;
    }

    UUID addProgram(string source, string[] kernelNames)
    {
        auto program = randomUUID;
        this._programs[program] = new ClProgram(this, source, kernelNames);
        return program;
    }

    void removeProgram(UUID program)
    {
        if(program in this._programs)
        {
            this._programs[program].release();
            this._programs.remove(program);
        }
    }

    UUID addMemory(string name, TypeInfo type, size_t size)
    {
        auto id = randomUUID;

        return id;
    }

    void removeMemory(UUID memory)
    {

    }

    private void createClContext()
    {
        cl_int status = 0;
        this._clId = clCreateContext(null, cast(uint)1, &this.device._clId, null, null, &status);

        if(status != CL_SUCCESS)
            throw(ClException.get("clCreateContext", status));
    }

    void dispose()
    {
        this.queue.release();
        foreach(p; this._programs)
            p.release();
        this._state = ClContextState.Stopped;
    }
}

class ClFactory
{
    import core.sync.rwmutex;
    private static ReadWriteMutex _lock;
    private static ClContext[UUID] _sessions;

    shared static this()
    {
        _lock = new ReadWriteMutex(ReadWriteMutex.Policy.PREFER_WRITERS);
        DerelictCL.load();
        DerelictCL.reload(CLVersion.CL12);
    }

    static ClContext get(string[] requiredExtensions = [])
    {
        synchronized(_lock.writer)
        {            
            auto id = randomUUID;
            _sessions[id] = new ClContext(id, requiredExtensions);            
            return _sessions[id];
        }
    }

    static ClContext get(UUID id)
    {
        synchronized(_lock.reader)
            return _sessions[id];
    }

    static void dispose(UUID id)
    {
        synchronized(_lock.writer)
        {
            if(id != UUID.init)
            {
                try{_sessions[id].dispose();}
                finally {_sessions.remove(id);}
            }
        }
    }
}