module flow.data.memory;

import std.uuid, std.array, std.datetime;

import flow.base.blocks, flow.base.signals, flow.base.data, flow.base.interfaces;

class RevisionInfo : Data {
    mixin data;

    mixin field!(long, "id");
    mixin field!(DateTime, "time");
}

/// holds a list of revisions for specific data
class MemoryInfo : IdData {
    mixin data;

    mixin field!(string, "name");
    mixin field!(string, "description");
    mixin list!(RevisionInfo, "revisions");
}

/// adresses a specific revision of specific data
class RequestInfo : IdData {
    mixin data;

    mixin field!(long, "revision");
}

/// meta informations of data stored in url
class MemoryInfos : Data {
    mixin data;

    mixin list!(string, "types");
    mixin list!(MemoryInfo, "data");
}

/// file format enumeration
enum MemoryFormat : uint {
    Json = 1
}

/// context of memory entity
class MemoryContext : Data {
    mixin data;

    mixin field!(MemoryConfig, "settings");
    mixin field!(MemoryInfos, "infos");
}

/// settings of memory entity
class MemoryConfig : EntityConfig {
    mixin data;
    
    mixin list!(string, "types");
}

class FileMemoryConfig : MemoryConfig {
    mixin data;
    
    mixin field!(string, "url");
    mixin field!(MemoryFormat, "format");
}

/// container holding data
class MemoryContainer : IdData {
    mixin data;

    mixin field!(long, "revision");
    mixin field!(string, "name");
    mixin field!(string, "description");
    mixin field!(Data, "data");
}

/// stores data into memory
class StoreRequest : Unicast{mixin signal!(MemoryContainer);}

/// stores data into memory
class RemoveRequest : Unicast{mixin signal!(UUID);}

/// requests a list of held data
class OverviewRequest : Unicast{mixin signal!();}

/// requests info of specific data
class InfoRequest : Unicast{mixin signal!(UUID);}

/// requests specific data of a specific revision
class Request : Unicast{mixin signal!(RequestInfo);}

/// requests new data of specific type
class RequestNew : Unicast{mixin signal!(string);}

/// informing the swarm a memory was added
class AddedMsg : Multicast{mixin signal!(UUID);}

/// informing the swarm a memory was updated
class UpdateMsg : Multicast{mixin signal!(UUID);}

/// informing the swarm a memory was deleted
class RemoveMsg : Multicast{mixin signal!(UUID);}

/// can memory store a specific data type?
private bool canStore(MemoryConfig se, MemoryContainer d) {
    import std.algorithm.searching;

    return d !is null && d.data !is null &&
           d.id != UUID.init &&
           se.types.array.any!(t=>t== d.data.dataType);
}

/// do memory contain specific data
private bool contains(MemoryContext c, UUID d) {
    import std.algorithm.searching;

    return d != UUID.init &&
           c.infos.data.array.any!(i=>i.id == d);
}

/// do memory contain a specific revision of specific data
private bool contains(MemoryContext c, RequestInfo d) {
    import std.algorithm.searching;

    return d.id != UUID.init &&
        c.infos.data
        .array.any!(
            i=>i.id == d.id &&
            i.revisions.array.any!(r=>r.id == d.revision));
}

/// inform swarm that memories were loaded
class LoadedMsg : Multicast{mixin signal!();}
class Loaded : Tick {
	mixin tick;

	override void run()
	{
        import flow.base.dev;
        
        this.msg(DL.Debug, "memory successfully loaded");
        this.answer(new LoadedMsg);
    }
}

/// inform the requestor memory isn't loaded yet
class NotLoadedMsg : Unicast{mixin signal!();}

class NotLoaded : Tick {
	mixin tick;

	override void run()
	{
        this.answer(new NotLoadedMsg);
    }
}

RevisionInfo lastRevOf(MemoryInfo i, UUID id) {
    import std.algorithm.comparison, std.algorithm.iteration;

    if(!i.revisions.empty)
        return i.revisions.back;

    return null;
}

enum StoreType {
    Add,
    Update
}
class StoreSuccessMsg : Unicast{mixin signal!(string);}
class StoreFailedMsg : Unicast{mixin signal!(string);}

/// stores data to disk
class Store : Tick {
	mixin tick;

	override void run()
	{
        import std.conv, std.algorithm.iteration;

        auto s = this.signal.as!StoreRequest;
        auto c = this.context.as!MemoryContext;
        auto cfg = this.entity.config.as!MemoryConfig;

        if(!cfg.canStore(s.data))
            this.answer(new IncompatibleResponse);
        else {
            MemoryInfo mi;
            if(c.contains(s.data.id))
                mi = c.infos.data.array.filter!(i=>i.id == s.data.id).front;
            else
            {
                mi = new MemoryInfo;
                mi.id = s.data.id;
                c.infos.data.put(mi);
            }

            mi.name = s.data.name;
            mi.description = s.data.description;

            auto revision = new RevisionInfo;
            auto lr = mi.lastRevOf(s.data.id);
            revision.id = lr !is null ? lr.id + 1 : 0;
            s.data.revision = revision.id;
            revision.time = Clock.currTime.toUTC().as!DateTime;
            mi.revisions.put(revision);

            auto mc = s.data.as!MemoryContainer;
            auto st = this.entity.as!Memory.store(mc);

            if(st == StoreType.Add)
            {
                auto ns = new AddedMsg;
                ns.data = s.data.id;
                this.send(ns);
            }
            else if(st == StoreType.Update)
            {
                auto ns = new UpdateMsg;
                ns.data = s.data.id;
                this.send(ns);
            }

            this.answer(new StoreSuccessMsg);
        }
    }
    
    override void error(Exception e)
    {
        auto ns = new StoreFailedMsg;
        ns.data = e.msg;
        this.answer(ns);
    }
}

/// inform the requestor memory cannot store that data type
class IncompatibleResponse : Unicast{mixin signal!();}

/// inform requestor that data or revision wasn't found
class NotFoundMsg : Unicast{mixin signal!();}

class RemoveSuccessMsg : Unicast{mixin signal!(string);}
class RemoveFailedMsg : Unicast{mixin signal!(string);}

class Remove : Tick {
	mixin tick;

	override void run()
	{
        import std.conv, std.algorithm.iteration;
        import flow.base.dev;

        auto s = this.signal.as!RemoveRequest;
        auto c = this.context.as!MemoryContext;
        auto id = s.data;

        if(!c.contains(s.data))
            this.answer(new NotFoundMsg);
        else {
            MemoryInfo mi = c.infos.data.array.filter!(i=>i.id == id).front;
            c.infos.data.remove(mi);

            this.entity.as!Memory.remove(id);

            auto ns = new RemoveMsg;
            ns.data = id;
            this.send(ns);

            this.answer(new RemoveSuccessMsg);
        }
    }
    
    override void error(Exception e)
    {
        auto ns = new RemoveFailedMsg;
        ns.data = e.msg;
        this.answer(ns);
    }
}

/// holds a list of data
class StoredInfo : Data {
	mixin data;

    mixin list!(UUID, "data");
}

class OverviewResponse : Unicast{mixin signal!(StoredInfo);}

class SendList : Tick {
	mixin tick;

	override void run()
	{
        import std.algorithm.iteration;

        auto c = this.context.as!MemoryContext;

        auto si = new StoredInfo;
        si.data.put(c.infos.data.array.map!(i=>i.id).array);

        auto r = new OverviewResponse;
        r.data = si;
        this.answer(r);
    }
}

/// response to InfoRequest
class InfoResponse : Unicast{mixin signal!(MemoryInfo);}

class SendRevisions : Tick {
	mixin tick;

	override void run()
	{
        import std.algorithm.iteration;

        auto c = this.context.as!MemoryContext;
        auto s = this.signal.as!InfoRequest;

        if(!c.contains(s.data))
            this.answer(new NotFoundMsg);
        else {
            auto mi = c.infos.data.array.filter!(i=>i.id == s.data).front;
            auto r = new InfoResponse;
            r.data = mi;
            this.answer(r);
        }
    }
}

/// answer to Request
class Response : Unicast{mixin signal!(MemoryContainer);}

class Send : Tick {
	mixin tick;

	override void run()
	{
        auto s = this.signal.as!Request;
        auto c = this.context.as!MemoryContext;

        if(!c.contains(s.data))
            this.answer(new NotFoundMsg);
        else {
            auto data = this.entity.as!Memory.get(s.data.id, s.data.revision);

            auto rs = new Response;
            rs.data = data;
            this.answer(rs);
        }
    }
}

class SendNew : Tick {
	mixin tick;

	override void run()
	{
        auto s = this.signal.as!RequestNew;
        auto c = this.context.as!MemoryContext;

        auto cont = new MemoryContainer;
        cont.id = randomUUID;
        cont.revision = -1;
        cont.name = "Unnamed";
        cont.description = "";
        cont.data = Data.create(s.data).as!Data;

        auto rs = new Response;
        rs.data = cont;
        this.answer(rs);
    }
}

class UrlNotValidException : Exception
{this(string msg){super(msg);}}

class UrlIncompatibleException : Exception
{this(string msg){super(msg);}}

class UrlContainsUnknownMemoriesException : Exception
{this(string msg){super(msg);}}

class NoStorageException : Exception
{this(string msg){super(msg);}}

abstract class MemoryStorage {
    protected Memory _memory;

    this(Memory memory)
    {
        this._memory = memory;
    }

    void start(){}
    void stop(){}
    abstract protected MemoryContainer get(UUID id, long revId);
    abstract protected StoreType store(MemoryContainer mc);
    abstract protected void remove(UUID id);
}

class FileMemoryStorage : MemoryStorage {
    this(Memory memory){super(memory);}

    override void start()
    {
        import std.file, std.path, std.algorithm.searching;

        auto c = this._memory.context.as!MemoryContext;
        auto se = c.settings.as!FileMemoryConfig;

        if(se.url.isValidPath && se.url.isDir)
        {
            auto listFile = se.url.buildPath("list");
            if(!listFile.exists)
            {
                c.infos = new MemoryInfos;
                c.infos.types.put(se.types.array);
                listFile.write(c.infos.json);
            }
            else if(listFile.isFile)
            {
                auto listFileContent = read(listFile).as!string;

                if(listFileContent !is null && listFileContent != "")
                {
                    c.infos = Data.fromJson(listFileContent).as!MemoryInfos;

                    if(!c.settings.types.array.all!(t1 => se.types.array.any!(t2 => t2 == t1)))
                        throw new UrlContainsUnknownMemoriesException("\""~se.url~"\" memory doesn't manage one or more contained data types");
                }
            }
            else throw new UrlIncompatibleException("\""~se.url~"\" contains unknown data");
        }
        else throw new UrlNotValidException("\""~se.url~"\" is no valid directory");
    }

    override protected MemoryContainer get(UUID id, long revId)
    {
        auto c = this._memory.context.as!MemoryContext;
        auto se = c.settings.as!FileMemoryConfig;
        import std.file, std.path, std.conv, std.algorithm.iteration, std.algorithm.searching;
        import flow.base.dev;

        auto mi = c.infos.data.array.filter!(i=>i.id == id).front;
        if(mi.revisions.array.any!(r=>r.id == revId))
        {
            auto revision = mi.revisions.array.filter!(r=>r.id == revId).front;

            auto dataPath = se.url.buildPath(id.toString);
                
            auto revisionPath = dataPath.buildPath(revision.id.to!string ~ ".dat");
            MemoryContainer d;
            if(se.format == MemoryFormat.Json)
                return Data.fromJson(revisionPath.read().as!string).as!MemoryContainer;
        }

        return null;
    }

    override protected StoreType store(MemoryContainer mc)
    {
        import std.file, std.path, std.conv;
        auto c = this._memory.context.as!MemoryContext;
        auto se = c.settings.as!FileMemoryConfig;
        auto dataPath = se.url.buildPath(mc.id.toString);
        auto exists = dataPath.exists;
        if(!exists)
            dataPath.mkdir();
            
        auto revisionPath = dataPath.buildPath(mc.revision.to!string ~ ".dat");
        if(se.format == MemoryFormat.Json)
            revisionPath.write(mc.json);

        auto listFile = se.url.buildPath("list");
        listFile.write(c.infos.json);

        return exists ? StoreType.Update : StoreType.Add;
    }

    override protected void remove(UUID id)
    {
        import std.file, std.path;
        auto c = this._memory.context.as!MemoryContext;
        auto se = c.settings.as!FileMemoryConfig;
        auto dataPath = se.url.buildPath(id.toString);
        dataPath.rmdirRecurse();

        auto listFile = se.url.buildPath("list");
        listFile.write(c.infos.json);
    }
}

class Memory : Entity
{
    mixin entity;

    mixin listen!(fqn!OverviewRequest, fqn!SendList);
    mixin listen!(fqn!StoreRequest, fqn!Store);
    mixin listen!(fqn!RemoveRequest, fqn!Remove);
    mixin listen!(fqn!InfoRequest, fqn!SendRevisions);
    mixin listen!(fqn!Request, fqn!Send);
    mixin listen!(fqn!RequestNew, fqn!SendNew);

    private MemoryStorage _storage;
    @property MemoryStorage storage() {return this._storage;}
    @property void storage(MemoryStorage value) {this._storage = value;}

    override void start()
    {        
        if(this._storage !is null)
            this._storage.start();
        //else throw new NoStorageException("storage missing");
    }

    override void stop()
    {
        if(this._storage !is null)
            this._storage.stop();
        //else throw new NoStorageException("storage missing");
    }

    MemoryContainer get(UUID id, long revId)
    {
        if(this._storage !is null)
            return this._storage.get(id, revId);
        else throw new NoStorageException("storage missing");
    }

    StoreType store(MemoryContainer mc)
    {
        if(this._storage !is null)
            return this._storage.store(mc);
        else throw new NoStorageException("storage missing");
    }

    void remove(UUID id)
    {
        if(this._storage !is null)
            this._storage.remove(id);
        else throw new NoStorageException("storage missing");
    }
}