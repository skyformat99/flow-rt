module flow.net.web;

import std.uuid, std.array, std.string, std.datetime, std.conv, std.algorithm.searching, std.algorithm.iteration, std.file, std.path;

import flow.sws.webServer, flow.sws.webRequest;
import flow.flow.entity;
import flow.base.dev, flow.base.blocks, flow.base.data, flow.base.interfaces, flow.base.signals;

class StartWebService : Unicast{mixin signal!();}
class StopWebService : Unicast{mixin signal!();}
class WebSignalData : Data
{
	mixin data;

    mixin field!(string, "signal");
}
class WebSignal : Unicast, IStealth {mixin signal!(WebSignalData);}

class WebSessionRequestData : Data
{
	mixin data;

    mixin list!(string, "listenings");
}

class WebSessionContext : Data
{
	mixin data;

    mixin field!(EntityRef, "service");
}

class WebSessionListening : IdData
{
    mixin data;

    mixin field!(string, "signal");
    mixin list!(UUID, "sources");
}

class WebSessionInfo : Data
{
	mixin data;

    mixin field!(EntityRef, "session");
    mixin field!(DateTime, "lastActivity");
    mixin list!(WebSessionListening, "listenings");
    mixin list!(WebSignal, "inQueue");
}

class WebServiceContext : Data
{
	mixin data;

    mixin field!(UUID, "server");
    mixin field!(ushort, "port");
    mixin field!(ushort, "listenerAmount");
    mixin field!(string, "root");
    mixin field!(string, "error");
    mixin list!(WebSessionInfo, "sessions");
}

private class WebServiceServer : WebServer
{
    import core.sync.mutex;
    private static Mutex _lock;
    private static WebServiceServer[UUID] _listenerReg;

    shared static this()
    {
        _lock = new Mutex;
    }

    static UUID add(IEntity entity, ushort port, ushort listenerAmount, bool delegate(IEntity, WebRequest) handleReq, bool delegate(IEntity, WebRequest, string) handleMsg)
    {
        synchronized(_lock)
        {
            auto id = randomUUID;
            _listenerReg[id] = new WebServiceServer(entity, port, handleReq, handleMsg);
            _listenerReg[id].listenerAmount = listenerAmount;
            _listenerReg[id].start();
            return id;
        }
    }

    static void remove(UUID id)
    {
        synchronized(_lock)
        {
            if(id in _listenerReg)
            {
                _listenerReg[id].stop();
                _listenerReg.remove(id);
            }
        }
    }

    private IEntity _entity;
    private ushort _port;
    private bool delegate(IEntity, WebRequest) _handleReq;
    private bool delegate(IEntity, WebRequest, string) _handleMsg;

    @property ushort port(){return this._port;}

    private this(IEntity entity, ushort port, bool delegate(IEntity, WebRequest) handleReq, bool delegate(IEntity, WebRequest, string) handleMsg)
    {
        this._entity = entity;
        this._port = port;
        this._handleReq = handleReq;
        this._handleMsg = handleMsg;
        super();
        setPort(port);
    }

    override bool processRequest(WebRequest req) {
        return this._handleReq(this._entity, req);
    }

    override bool processMessage(WebRequest req, string msg) {
        return this._handleMsg(this._entity, req, msg);
    }
}

private bool onWebRequestSession(IEntity e, WebRequest req)
{
    auto c = e.context.as!WebServiceContext;

    debugMsg("web request \""~req.url~"\" is a session request", 2);
    
    try
    {
        UUID existing;
        try{existing = parseUUID(req.getCookie("flowsession"));}catch(Exception exc){}
        if(existing != UUID.init && c.sessions.array.any!(i=>i.session.id == existing))
        {
            auto session = c.sessions.array.filter!(i=>i.session.id == existing).front;
            e.hull.remove(existing);
            c.sessions.remove(session);
        }

        auto sc = new WebSessionContext;
        sc.service = e.info.reference;
        auto session = new WebSession(randomUUID, e.info.domain, e.info.availability, sc);
        e.hull.add(session);

        auto info = new WebSessionInfo;
        info.session = session.info.reference;
        info.lastActivity = Clock.currTime.toUTC().as!DateTime;
        c.sessions.put(info);
        req.setCookie("flowsession", session.id.toString);
        debugMsg("web request \""~req.url~"\" added web session with id \""~session.id.toString()~"\"", 2);

        req.sendText("true");
        return true;
    }
    catch(Exception exc)
    {
        debugMsg("web request \""~req.url~"\" caused an exception \""~exc.msg~"\"", 2);
    }
    
    req.sendText("false");
    return false;
}

private bool onWebRequestValidateSession(IEntity e, WebRequest req)
{
    auto c = e.context.as!WebServiceContext;

    debugMsg("web request \""~req.url~"\" is a validate session request", 2);
    
    try
    {
        UUID existing;
        try{existing = parseUUID(req.getCookie("flowsession"));}catch(Exception exc){}

        if(existing != UUID.init && c.sessions.array.any!(i=>i.session.id == existing))
        {
            req.sendText("true");
            return true;
        }
        else
        {
            req.setCookie("flowsession", null);
        }
    }
    catch(Exception exc)
    {
        debugMsg("web request \""~req.url~"\" caused an exception \""~exc.msg~"\"", 2);
    }
    
    req.sendText("false");
    return false;
}

private bool onWebRequestEndSession(IEntity e, WebRequest req)
{
    debugMsg("web request \""~req.url~"\" is a end session request", 2);

    try
    {
        UUID existing;
        try{existing = parseUUID(req.getCookie("flowsession"));}
        catch(Exception exc)
        {
            debugMsg("web request \""~req.url~"\" contains has no valid session id \""~req.getCookie("flowsession")~"\"", 3);
            req.sendError(400, "no valid session id<br>"~req.getCookie("flowsession"));
        }

        auto c = e.context.as!WebServiceContext;
        if(existing != UUID.init && c.sessions.array.any!(i=>i.session.id == existing))
        {
            auto info = c.sessions.array.filter!(i=>i.session.id == existing).front;
            auto session = e.hull.get(existing);

            e.hull.remove(existing);
            c.sessions.remove(info);
            req.setCookie("flowsession", null);
            debugMsg("web request \""~req.url~"\" removed web session with id \""~existing.toString()~"\"", 2);

            req.sendText("true");
            return true;
        }
    }
    catch(Exception exc)
    {
        debugMsg("web request \""~req.url~"\" caused an exception \""~exc.msg~"\"", 2);
    }
    
    req.sendText("false");
    return false;
}

private Object webListenHandler(IEntity e, ISignal s)
{
    debugMsg("web session received \""~s.type~"\"", 2);
    auto service = e.hull.get(e.context.as!WebSessionContext.service.id);
    auto c = service.context.as!WebServiceContext;
    auto info = c.sessions.array.filter!(i => i.session.id == e.id).front;
    foreach(l; info.listenings.array.filter!(l => l.signal == s.type))
    {
        foreach(src; l.sources.array.filter!(src => src == UUID.init || src == s.source.id))
            return new PushWebSignal;
            
        break;
    }

    return null;
}

private bool onWebRequestAddListenSource(IEntity e, WebRequest req)
{
    debugMsg("web request \""~req.url~"\" is an add listen source request", 2);
    try
    {
        UUID existing;
        try{existing = parseUUID(req.getCookie("flowsession"));}
        catch(Exception exc)
        {
            debugMsg("web request \""~req.url~"\" contains has no valid session id \""~req.getCookie("flowsession")~"\"", 3);
            req.sendError(400, "no valid session id<br>"~req.getCookie("flowsession"));
        }
        
        auto c = e.context.as!WebServiceContext;
        if(existing != UUID.init && c.sessions.array.any!(i => i.session.id == existing))
        {
            auto data = req.rawData.strip();
            auto signal = data.split(";")[0];
            auto source = data.split(";")[1];
            auto id = source == "*" ? UUID.init : parseUUID(source);
            auto info = c.sessions.array.filter!(i => i.session.id == existing).front;
            
            if(!info.listenings.array.any!(l => l.signal == signal))
            {
                debugMsg(existing.to!string~" listening to \""~signal~"\"", 2);

                auto lid = e.hull.get(existing).beginListen(signal, (e, s) => webListenHandler(e, s));
                auto listening = new WebSessionListening;
                listening.id = lid;
                listening.signal = signal;
                info.listenings.put(listening);
            }

            debugMsg(existing.to!string~" allowing \""~id.to!string~"\" for \""~signal~"\"", 2);
            auto listening = info.listenings.array.filter!(l => l.signal == signal).front;
            if(!listening.sources.array.any!(src => src == id))
                listening.sources.put(id);

            req.sendText("true");
            return true;
        }
    }
    catch(Exception exc)
    {
        debugMsg("web request \""~req.url~"\" caused an exception \""~exc.msg~"\"", 2);
    }
    
    req.sendText("false");
    return false;
}

private bool onWebRequestRemoveListenSource(IEntity e, WebRequest req)
{
    debugMsg("web request \""~req.url~"\" is a remove listen source request", 2);
    try
    {
        UUID existing;
        try{existing = parseUUID(req.getCookie("flowsession"));}
        catch(Exception exc)
        {
            debugMsg("web request \""~req.url~"\" contains has no valid session id \""~req.getCookie("flowsession")~"\"", 3);
            req.sendError(400, "no valid session id<br>"~req.getCookie("flowsession"));
        }
        
        auto c = e.context.as!WebServiceContext;
        if(existing != UUID.init && c.sessions.array.any!(i => i.session.id == existing))
        {
            auto data = req.rawData.strip();
            auto signal = data.split(";")[0];
            auto source = data.split(";")[1];
            auto id = source == "*" ? UUID.init : parseUUID(source);
            auto info = c.sessions.array.filter!(i => i.session.id == existing).front;
            if(info.listenings.array.any!(l => l.signal == signal))
            {
                auto listening = info.listenings.array.filter!(l => l.signal == signal).front;
                if(listening.sources.array.any!(src => src == id))
                    listening.sources.remove(id);

                if(listening.sources.length == 0)
                {
                    info.listenings.remove(listening);
                    e.hull.get(existing).endListen(listening.id);
                }

                req.sendText("true");
                return true;
            }
        }
    }
    catch(Exception exc)
    {
        debugMsg("web request \""~req.url~"\" caused an exception \""~exc.msg~"\"", 2);
    }
    
    req.sendText("false");
    return false;    
}

private bool onWebRequestReceive(IEntity e, WebRequest req)
{
    debugMsg("web request \""~req.url~"\" is a receive request", 2);

    UUID existing;
    try{existing = parseUUID(req.getCookie("flowsession"));}
    catch(Exception exc)
    {
        debugMsg("web request \""~req.url~"\" contains has no valid session id \""~req.getCookie("flowsession")~"\"", 3);
        req.sendError(400, "no valid session id<br>"~req.getCookie("flowsession"));
    }

    auto c = e.context.as!WebServiceContext;
    if(existing != UUID.init && c.sessions.array.any!(i=>i.session.id == existing))
    {
        auto info = c.sessions.array.filter!(i=>i.session.id == existing).front;
        WebSignal[] signals;
        synchronized
        {
            signals ~= info.inQueue.array;
            info.inQueue.clear();
        }
    
        debugMsg("web request \""~req.url~"\" found "~signals.length.to!string~" new signals", 3);
        auto signalsString = "[";
        foreach(ws; signals)
            signalsString ~= ws.data.signal~",";
        if(signalsString[$-1..$] == ",")
            signalsString = signalsString[0..$-1];
        signalsString ~= "]";

        req.sendText(signalsString);
    }
    
    return true;
}

private bool onWebRequestSend(IEntity e, WebRequest req)
{
    import flow.base.signals;

    debugMsg("web request \""~req.url~"\" is a send request", 2);

    UUID existing;
    try{existing = parseUUID(req.getCookie("flowsession"));}
    catch(Exception exc)
    {
        debugMsg("web request \""~req.url~"\" has no valid session id \""~req.getCookie("flowsession")~"\"", 3);
        req.sendError(400, "no valid session id<br>"~req.getCookie("flowsession"));
    }

    auto c = e.context.as!WebServiceContext;
    if(existing != UUID.init && c.sessions.array.any!(i=>i.session.id == existing))
    {
        auto se = c.sessions.array.filter!(i=>i.session.id == existing).front;
        auto data = req.rawData.strip();
        ISignal s;
        try
        {
            s = Data.fromJson(data).as!ISignal;
            if(s !is null)
            {
                s.source = e.hull.get(se.session.id).info.reference;
                s.type = s.dataType;
                if(s.group == UUID.init) s.group = randomUUID;
            }
        }
        catch(Exception exc)
        {
            debugMsg("web request \""~req.url~"\" contains malformed data \""~data~"\" \""~exc.msg~"\"", 3);
            req.sendError(400, "malformed send request<br>"~exc.msg);
        }

        if(s !is null)
        {
            auto success = false;
            if(s.as!IUnicast !is null)
                success = e.hull.send(s.as!IUnicast);
            else if(s.as!IMulticast !is null)
                success = e.hull.send(s.as!IMulticast);
            else if(s.as!IAnycast !is null)
                success = e.hull.send(s.as!IAnycast);
            
            auto session = e.hull.get(existing);
            if(e.hull.tracing &&
                s.as!IStealth is null)
            {
                auto tsd = new TraceSignalData;
                auto tss = new TraceSend;
                tss.type = tss.dataType;
                tss.source = s.source;
                tss.data = tsd;
                tss.data.success = success;
                tss.data.group = s.group;
                tss.data.nature = s.as!IUnicast !is null ?
                    "Unicast" : (
                        s.as!IMulticast !is null ? "Multicast" :
                        "Anycast"
                    );
                tss.data.trigger = existing;
                if(s.as!IUnicast !is null)
                    tss.data.destination = s.as!IUnicast.destination;
                tss.data.time = Clock.currTime.toUTC();
                tss.data.id = s.id;
                tss.data.type = s.type;
                e.hull.send(tss);

                auto ttd = new TraceTickData;
                auto tts = new TraceEndTick;
                tts.type = tts.dataType;
                tts.source = session.info.reference;
                tts.data = ttd;
                tts.data.id = session.id;
                tts.data.time = Clock.currTime.toUTC();
                tts.data.entityType = session.__fqn;
                tts.data.entityId = session.id;
                tts.data.tick = session.__fqn;
                e.hull.send(tts);
            }                
                
            req.sendText(success ? "true" : "false");
        }
        else
        {
            debugMsg("web request \""~req.url~"\" contains malformed data \""~data~"\"", 3);
            req.sendError(400, "malformed send request<br>"~data);
        }
    }
    
    return true;
}

private bool onWebRequestFile(IEntity e, WebRequest req)
{
    debugMsg("web request \""~req.url~"\" is a file request", 2);

    auto c = e.context.as!WebServiceContext;
    auto file = req.url;

    if(file[0..1] == dirSeparator)
        file = file[1..$];

    if(file == "")
        file = "index.html";

    file = file.replace("/", dirSeparator);

    file = c.root.buildPath(file);

    if(file.isValidPath && file.exists && file.isFile)
    {
        req.sendFile(file);
        return true;
    }
    else
    {
        debugMsg("\""~file~"\" not found", 3);
        req.sendError(404, "file not found");
    }

    return false;
}

private bool onWebRequest(IEntity e, WebRequest req)
{
    debugMsg("got web request \""~req.url~"\"", 1);
    auto ret = false;
    if(req.matchUrl("\\/::flow::.*"))
    {
        debugMsg("web request \""~req.url~"\" is a flow request", 2);
        if(req.url == "/::flow::requestSession")
            ret = onWebRequestSession(e, req);
        else if(req.url == "/::flow::validateSession")
            ret = onWebRequestValidateSession(e, req);
        else if(req.url == "/::flow::destroySession")
            ret = onWebRequestEndSession(e, req);
        else if(req.url == "/::flow::addListenSource")
            ret = onWebRequestAddListenSource(e, req);
        else if(req.url == "/::flow::removeListenSource")
            ret = onWebRequestRemoveListenSource(e, req);
        else if(req.url == "/::flow::receive")
            ret = onWebRequestReceive(e, req);
        else if(req.url == "/::flow::send")
            ret = onWebRequestSend(e, req);
        else
        {
            debugMsg("web request \""~req.url~"\" is unknown'", 3);
            req.sendError(400, "unknown request");
        }
    }
    else
    {
        ret = onWebRequestFile(e, req);
    }

    req.flush;
    debugMsg("web request \""~req.url~"\" flushed'", 3);
    return ret;
}

private bool onWebMessage(IEntity e, WebRequest req, string msg)
{
    return true;
}

class WebServiceStart : Tick
{
	mixin tick;

	override void run()
	{
        //this.ticker.fork(new CheckSessions);
    }
}

class WebServiceStop : Tick
{
	mixin tick;

	override void run()
	{
        auto c = this.entity.context.as!WebServiceContext;
        c.server = UUID.init;
    }
}

class WebServiceStartError : Tick
{
	mixin tick;

	override void run()
	{

    }
}

class WebServiceStopError : Tick
{
	mixin tick;

	override void run()
	{

    }
}

class WebServiceAlreadyStarted : Tick
{
	mixin tick;

	override void run()
	{

    }
}

class WebServiceAlreadyStopped : Tick
{
	mixin tick;

	override void run()
	{

    }
}

private Object onStartWebService(IEntity entity, ISignal s)
{
    auto c = entity.context.as!WebServiceContext;

    if(c.server == UUID.init)
    {
        try
        {
            c.server = WebServiceServer.add(
                entity, 
                c.port,
                c.listenerAmount,
                (e, req) => onWebRequest(e, req), 
                (e, req, msg) => onWebMessage(e, req, msg)
            );
            
            return new WebServiceStart;
        }
        catch(Exception exc)
        {
            c.error= exc.toString();
            return new WebServiceStartError;
        }
    }
    
    return new WebServiceAlreadyStarted;
}

private Object onStopWebService(IEntity entity, ISignal s)
{
    auto c = entity.context.as!WebServiceContext;

    if(c.server != UUID.init)
    {
        try
        {
            WebServiceServer.remove(c.server);
            
            return new WebServiceStop;
        }
        catch(Exception exc)
        {
            c.error= exc.toString();
            return new WebServiceStopError;
        }
    }
    
    return new WebServiceAlreadyStopped;
}

class PullWebSignal : Tick
{
	mixin tick;

	override void run()
	{
        auto s = this.trigger.as!WebSignal;
        auto c = this.entity.context.as!WebServiceContext;

        if(c.sessions.array.any!(i=>i.session.id == s.source.id))
        {
            auto info = c.sessions.array.filter!(i=>i.session.id == s.source.id).front;
            auto session = this.entity.hull.get(s.source.id);
            if(this.entity.hull.tracing && s.as!IStealth is null)
            {
                auto td = new TraceTickData;
                auto ts = new TraceBeginTick;
                ts.type = ts.dataType;
                ts.source = session.info.reference;
                ts.data = td;
                ts.data.id = session.id;
                ts.data.time = Clock.currTime.toUTC();
                ts.data.entityType = session.__fqn;
                ts.data.entityId = session.id;
                ts.data.tick = session.__fqn;
                this.entity.hull.send(ts);
            }

            info.inQueue.put(s);
        }
        else // this session should not exist, so kill it
        {
            this.entity.hull.remove(s.source.id);
        }
    }
}

class PushWebSignal : Tick, IStealth
{
	mixin tick;

	override void run()
	{
        auto c = this.entity.context.as!WebSessionContext;
        auto wd = new WebSignalData;
        wd.signal = this.trigger.toJson();
        auto ws = new WebSignal;
        ws.data = wd;
        this.send(ws, c.service);
    }
}

class WebSession : Entity, IQuiet
{
    mixin entity!(WebSessionContext);

    /*mixin listen!(fqn!WebSignal,
        (e, s) => new PushWebSignal
    );*/
}

class WebService : Entity, IStealth, IQuiet
{
    mixin entity!(WebServiceContext);

    mixin listen!(fqn!StartWebService,
        (e, s) => onStartWebService(e, s)
    );
    
    mixin listen!(fqn!WebSignal,
        (e, s) => new PullWebSignal
    );

    mixin listen!(fqn!StopWebService,
        (e, s) => onStopWebService(e, s)
    );
}

class WebConfig : Data
{
	mixin data;

    mixin field!(ushort, "port");
    mixin field!(ushort, "listenerAmount");
    mixin field!(string, "root");
}

class WebContext : Data
{
	mixin data;

    mixin field!(UUID, "service");
}

class Web : Organ
{
    mixin organ!(WebConfig);

    override IData start()
    {
        auto c = new WebContext;
        auto conf = config.as!WebConfig;

        auto sc = new WebServiceContext;
        sc.port = conf.port;
        sc.listenerAmount = conf.listenerAmount > 0 ? conf.listenerAmount : 10;
        sc.root = conf.root;
        auto webService = new WebService(sc);
        
        c.service = this.hull.add(webService);
        this.hull.send(new StartWebService, webService.info.reference);

        this.hull.wait(()=>sc.server != UUID.init);

        return c;
    }

    override void stop()
    {
        auto c = context.as!WebContext;
        auto sc = this.hull.get(c.service).context.as!WebServiceContext;

        this.hull.send(new StopWebService, this.hull.get(c.service).info.reference);
        this.hull.wait(()=>sc.server == UUID.init);

        this.hull.remove(c.service);
    }

    override @property bool finished()
    {
        auto c = context.as!WebContext;
        auto sc = this.hull.get(c.service).context.as!WebServiceContext;

        return sc.server == UUID.init;
    }
}