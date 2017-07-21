module flow.net.http;

import std.uuid, std.array, std.string, std.datetime, std.conv, std.algorithm.searching, std.algorithm.iteration, std.file, std.path;

import flow.sws.webServer, flow.sws.webRequest;
import __flow.entity;
import flow.base.dev, flow.base.blocks, flow.base.data, flow.base.interfaces, flow.base.signals;

import flow.net.beacon;

class HttpBeaconContext : BeaconContext {
	mixin data;

    mixin field!(UUID, "service");
    mixin field!(ushort, "port");
    mixin field!(ushort, "listenerAmount");
    mixin field!(string, "root");
}

private class HttpBeaconService : WebServer {
    import core.sync.mutex;
    private static Mutex _lock;
    private static HttpBeaconService[UUID] _listenerReg;

    shared static this() {
        _lock = new Mutex;
    }

    static UUID add(Entity entity, ushort port, ushort listenerAmount,
                    bool delegate(Entity, WebRequest) handleReq,
                    bool delegate(Entity, WebRequest, string) handleMsg) {
        synchronized(_lock) {
            auto id = randomUUID;
            _listenerReg[id] = new HttpBeaconService(entity, port, handleReq, handleMsg);
            _listenerReg[id].listenerAmount = listenerAmount;
            _listenerReg[id].start();
            return id;
        }
    }

    static void remove(UUID id) {
        synchronized(_lock) {
            if(id in _listenerReg) {
                _listenerReg[id].stop();
                _listenerReg.remove(id);
            }
        }
    }

    private Entity _entity;
    private ushort _port;
    private bool delegate(Entity, WebRequest) _handleReq;
    private bool delegate(Entity, WebRequest, string) _handleMsg;

    @property ushort port(){return this._port;}

    private this(Entity entity, ushort port,
                 bool delegate(Entity, WebRequest) handleReq,
                 bool delegate(Entity, WebRequest, string) handleMsg) {
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

class Read : Tick {
	mixin tick;

	override void run() {
        auto s = this.signal.as!WrappedSignal;
        auto c = this.context.as!BeaconContext;

        if(c.sessions.any!(ses=>ses.session.ptr.eq(s.source))) {
            // getting 
            auto session = c.sessions.filter!(ses=>ses.session.ptr.eq(s.source)).front;
            /*if(this.tracing && s.as!IStealth is null) {
                auto td = new TraceTickData;
                auto ts = new TraceBeginTick;
                ts.source = session.info.ptr;
                ts.data = td;
                ts.data.id = session.id;
                ts.data.time = Clock.currTime.toUTC();
                ts.data.entityType = session.__fqn;
                ts.data.entityId = session.id;
                ts.data.tick = session.__fqn;
                this.send(ts);
            }*/

            session.incoming.put(s);
        }
    }
}

class HttpBeacon : Beacon, IStealth {
    mixin entity;
    
    override void start() {
        auto c = this.context.as!HttpBeaconContext;
        c.service = HttpBeaconService.add(
            this, 
            c.port,
            c.listenerAmount,
            (e, req) => this.onWebRequest(req), 
            (e, req, msg) => this.onWebMessage(req, msg)
        );
    } 

    override void stop() {
        HttpBeaconService.remove(this.context.as!HttpBeaconContext.service);
    }

    private bool onHttpRequestSession(WebRequest req) {
        auto c = this.context.as!HttpBeaconContext;

        Log.msg(LL.Debug, "http request \""~req.url~"\" is a session request");
        
        try {
            EntityPtr ptr;
            BeaconSessionInfo session;
            try{ptr = Data.create(req.getCookie("flowsession")).as!EntityPtr;}catch(Exception exc){}

            if(ptr !is null && c.sessions.any!(i=>i.session.ptr.eq(ptr)))
                session = c.sessions.filter!(i=>i.session.ptr.eq(ptr)).front;
            else {
                auto sc = new BeaconSessionContext;
                sc.beacon = this.info.ptr;
                auto m = new EntityMeta;
                m.info = new EntityInfo;
                m.info.space = EntitySpace.Local;
                m.info.ptr = new EntityPtr;
                m.info.ptr.id = randomUUID.to!string;
                m.info.ptr.domain = this.info.ptr.domain;
                m.context = sc;

                session = new BeaconSessionInfo;
                session.session = this.spawn(m).info;
                session.lastActivity = Clock.currTime.toUTC().as!DateTime;
                c.sessions.put(session);
                auto json = session.session.ptr.json;
                req.setCookie("flowsession", json);
                Log.msg(LL.Info, "http request \""~req.url~"\" added session with ptr \""~json~"\"");
            }

            req.sendText("true");
            return true;
        } catch(Exception ex) {
            Log.msg(LL.Warning, ex, "http request \""~req.url~"\" failed");
        
            req.sendText("false");
            return false;
        }
    }

    private bool onHttpRequestValidateSession(WebRequest req)
    {
        auto c = this.context;

        Log.msg(LL.Debug, "http request \""~req.url~"\" is a validate session request");
        
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
        catch(Exception ex) {
            Log.msg(LL.Warning, ex, "http request \""~req.url~"\" failed");
        }
        
        req.sendText("false");
        return false;
    }

    private bool onHttpRequestEndSession(WebRequest req)
    {
        Log.msg(LL.Debug, "http request \""~req.url~"\" is a end session request");

        try
        {
            EntityPtr ptr;
            auto cookie = req.getCookie("flowsession");
            try{ptr = Data.create(cookie);}
            catch(Exception exc)
            {
                Log.msg(LL.Warning, ex, "http request \""~req.url~"\" contains has no valid session ptr \""~cookie~"\"");
                req.sendError(400, "no valid session id<br>"~req.getCookie("flowsession"));
            }

            auto c = this.context;
            if(ptr !is null && c.sessions.any!(i=>i.session.ptr.eq(ptr)))
            {
                auto info = c.sessions.array.filter!(i=>i.session.ptr.eq(ptr)).front;
                auto session = this.get(info);

                this.kill(info);
                c.sessions.remove(info);
                req.setCookie("flowsession", null);
                Log.msg(LL.Info, ptr, "http request \""~req.url~"\" removed session");

                req.sendText("true");
                return true;
            }
        }
        catch(Exception ex) {
            Log.msg(LL.Warning, ex, "http request \""~req.url~"\" failed");
        }
        
        req.sendText("false");
        return false;
    }

    private static Object httpListenHandler(Entity e, Signal s)
    {
        Log.msg(LL.Debug, s, "signal received");
        auto beacon = e.hull.get(e.context.as!BeaconSessionContext.beacon.id);
        
        auto c = beacon.context.as!HttpBeaconContext;
        auto info = c.sessions.array.filter!(i => i.session.id == e.id).front;
        foreach(l; info.listenings.array.filter!(l => l.signal == s.dataType))
        {
            foreach(src; l.sources.array.filter!(src => src == UUID.init || src == s.source.id))
                return new PushWrappedSignal;
                
            break;
        }

        return null;
    }

    private bool onHttpRequestAddListenSource(WebRequest req)
    {
        Log.msg(LL.Debug, "http request \""~req.url~"\" is an add listen source request");
        try
        {
            EntityPtr ptr;
            auto cookie = req.getCookie("flowsession");
            try{ptr = parseUUID(cookie);}
            catch(Exception exc)
            {
                Log.msg(LL.Warning, ex, "http request \""~req.url~"\" contains has no valid session id \""~cookie~"\"");
                req.sendError(400, "no valid session id<br>"~req.getCookie("flowsession"));
            }
            
            auto c = this.context.as!HttpBeaconContext;
            if(ptr !is null && c.sessions.any!(i => i.session.ptr.eq(ptr)))
            {
                auto data = req.rawData.strip();
                auto signal = data.split(";")[0];
                auto source = data.split(";")[1];
                auto id = source == "*" ? UUID.init : parseUUID(source);
                auto session = c.sessions.filter!(i => i.session.ptr.eq(ptr)).front;
                
                if(!session.listenings.any!(l => l.signal == signal))
                {
                    Log.msg(LL.Debug, existing.to!string~" listening to \""~signal~"\"", 2);

                    auto lid = this.get(existing).beginListen(signal, (e, s) => httpListenHandler(e, s));
                    auto listening = new BeaconSessionListening;
                    listening.id = lid;
                    listening.signal = signal;
                    info.listenings.put(listening);
                }

                Log.msg(LL.Debug, existing.to!string~" allowing \""~id.to!string~"\" for \""~signal~"\"", 2);
                auto listening = info.listenings.array.filter!(l => l.signal == signal).front;
                if(!listening.sources.array.any!(src => src == id))
                    listening.sources.put(id);

                req.sendText("true");
                return true;
            }
        }
        catch(Exception exc)
        {
            Log.msg(LL.Debug, "http request \""~req.url~"\" caused an exception \""~exc.msg~"\"", 2);
        }
        
        req.sendText("false");
        return false;
    }

    private bool onHttpRequestRemoveListenSource(WebRequest req)
    {
        Log.msg(LL.Debug, "http request \""~req.url~"\" is a remove listen source request", 2);
        try
        {
            UUID existing;
            try{existing = parseUUID(req.getCookie("flowsession"));}
            catch(Exception exc)
            {
                Log.msg(LL.Warning, "http request \""~req.url~"\" contains has no valid session id \""~req.getCookie("flowsession")~"\"", 3);
                req.sendError(400, "no valid session id<br>"~req.getCookie("flowsession"));
            }
            
            auto c = this.context;
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
                        this.hull.get(existing).endListen(listening.id);
                    }

                    req.sendText("true");
                    return true;
                }
            }
        }
        catch(Exception ex) {
            Log.msg(LL.Warning, "http request \""~req.url~"\" failed", ex);
        }
        
        req.sendText("false");
        return false;    
    }

    private bool onHttpRequestReceive(WebRequest req)
    {
        Log.msg(LL.Debug, "http request \""~req.url~"\" is a receive request", 2);

        UUID existing;
        try{existing = parseUUID(req.getCookie("flowsession"));}
        catch(Exception exc)
        {
            Log.msg(LL.Debug, "http request \""~req.url~"\" contains has no valid session id \""~req.getCookie("flowsession")~"\"", 3);
            req.sendError(400, "no valid session id<br>"~req.getCookie("flowsession"));
        }

        auto c = this.context;
        if(existing != UUID.init && c.sessions.array.any!(i=>i.session.id == existing))
        {
            auto info = c.sessions.array.filter!(i=>i.session.id == existing).front;
            WrappedSignal[] signals;
            synchronized
            {
                signals ~= info.inQueue.array;
                info.inQueue.clear();
            }
        
            Log.msg(LL.Debug, "http request \""~req.url~"\" found "~signals.length.to!string~" new signals", 3);
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

    private bool onHttpRequestSend(WebRequest req)
    {
        import flow.base.signals;

        Log.msg(LL.Debug, "http request \""~req.url~"\" is a send request", 2);

        UUID existing;
        try{existing = parseUUID(req.getCookie("flowsession"));}
        catch(Exception exc)
        {
            Log.msg(LL.Debug, "http request \""~req.url~"\" has no valid session id \""~req.getCookie("flowsession")~"\"", 3);
            req.sendError(400, "no valid session id<br>"~req.getCookie("flowsession"));
        }

        auto c = this.context;
        if(existing != UUID.init && c.sessions.array.any!(i=>i.session.id == existing))
        {
            auto se = c.sessions.array.filter!(i=>i.session.id == existing).front;
            auto data = req.rawData.strip();
            Signal s;
            try
            {
                s = Data.fromJson(data).as!Signal;
                if(s !is null)
                {
                    s.source = this.hull.get(se.session.id).info.ptr;
                    if(s.group == UUID.init) s.group = randomUUID;
                }
            }
            catch(Exception exc)
            {
                Log.msg(LL.Debug, "http request \""~req.url~"\" contains malformed data \""~data~"\" \""~exc.msg~"\"", 3);
                req.sendError(400, "malformed send request<br>"~exc.msg);
            }

            if(s !is null)
            {
                auto success = false;
                if(s.as!Unicast !is null)
                    success = this.hull.send(s.as!Unicast);
                else if(s.as!Multicast !is null)
                    success = this.hull.send(s.as!Multicast);
                else if(s.as!Anycast !is null)
                    success = this.hull.send(s.as!Anycast);
                
                auto session = this.hull.get(existing);
                if(this.hull.tracing &&
                    s.as!IStealth is null)
                {
                    auto tsd = new TraceSignalData;
                    auto tss = new TraceSend;
                    tss.source = s.source;
                    tss.data = tsd;
                    tss.data.success = success;
                    tss.data.group = s.group;
                    tss.data.nature = s.as!Unicast !is null ?
                        "Unicast" : (
                            s.as!Multicast !is null ? "Multicast" :
                            "Anycast"
                        );
                    tss.data.trigger = existing;
                    if(s.as!Unicast !is null)
                        tss.data.destination = s.as!Unicast.destination;
                    tss.data.time = Clock.currTime.toUTC();
                    tss.data.id = s.id;
                    tss.data.type = s.dataType;
                    this.hull.send(tss);

                    auto ttd = new TraceTickData;
                    auto tts = new TraceEndTick;
                    tts.type = tts.dataType;
                    tts.source = session.info.ptr;
                    tts.data = ttd;
                    tts.data.id = session.id;
                    tts.data.time = Clock.currTime.toUTC();
                    tts.data.entityType = session.__fqn;
                    tts.data.entityId = session.id;
                    tts.data.tick = session.__fqn;
                    this.hull.send(tts);
                }                
                    
                req.sendText(success ? "true" : "false");
            }
            else
            {
                Log.msg(LL.Debug, "http request \""~req.url~"\" contains malformed data \""~data~"\"", 3);
                req.sendError(400, "malformed send request<br>"~data);
            }
        }
        
        return true;
    }

    private bool onWebRequestFile(WebRequest req)
    {
        Log.msg(LL.Debug, "http request \""~req.url~"\" is a file request", 2);

        auto c = this.context;
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
            Log.msg(LL.Debug, "\""~file~"\" not found", 3);
            req.sendError(404, "file not found");
        }

        return false;
    }

    private bool onWebRequest(WebRequest req)
    {
        Log.msg(LL.Debug, "got http request \""~req.url~"\"", 1);
        auto ret = false;
        if(req.matchUrl("\\/::flow::.*"))
        {
            Log.msg(LL.Debug, "http request \""~req.url~"\" is a flow request", 2);
            if(req.url == "/::flow::requestSession")
                ret = this.onHttpRequestSession(req);
            else if(req.url == "/::flow::validateSession")
                ret = this.onHttpRequestValidateSession(req);
            else if(req.url == "/::flow::destroySession")
                ret = this.onHttpRequestEndSession(req);
            else if(req.url == "/::flow::addListenSource")
                ret = this.onHttpRequestAddListenSource(req);
            else if(req.url == "/::flow::removeListenSource")
                ret = this.onHttpRequestRemoveListenSource(req);
            else if(req.url == "/::flow::receive")
                ret = this.onHttpRequestReceive(req);
            else if(req.url == "/::flow::send")
                ret = this.onHttpRequestSend(req);
            else
            {
                Log.msg(LL.Debug, "http request \""~req.url~"\" is unknown'", 3);
                req.sendError(400, "unknown request");
            }
        }
        else
        {
            ret = this.onWebRequestFile(req);
        }

        req.flush;
        Log.msg(LL.Debug, "http request \""~req.url~"\" flushed'", 3);
        return ret;
    }

    private bool onWebMessage(WebRequest req, string msg)
    {
        return true;
    }
}