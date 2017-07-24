module __flow.tick;

import __flow.util, __flow.bound, __flow.data, __flow.log, __flow.error;
import flow.base.data;

import core.sync.rwmutex, core.thread;
import std.uuid;

class TickException : FlowException {
    mixin exception;
}

package enum TickerState {
    Stopped = 0,
    Started,
    Damaged
}

package class Ticker : StateMachine!TickerState {
    bool ticking;
    
    Bound bound;
    TickMeta actual;
    TickMeta coming;
    Exception error;

    private this(Bound b, Data c) {
        this.bound = b;
    }

    this(Bound b, Data c, Signal s, TickInfo initial) {
        this(b, c);
        this.coming = create(initial, s);
    }

    this(Bound b, Data c, TickMeta initial) {
        this(b, c);
        this.coming = initial;
    }

    override protected bool onStateChanging(TickerState o, TickerState n) {
        switch(n) {
            case TickerState.Started:
                return o == TickerState.Stopped;
            case TickerState.Stopped:
                return o == TickerState.Started;
            case TickerState.Damaged:
                return true;
            default: return false;
        }
    }

    override protected void onStateChanged(TickerState o, TickerState n) {
        switch(n) {
            case TickerState.Started:
                this.bound.tasker.run(&this.tick);
                break;
            case TickerState.Stopped:
                while(this.ticking)
                    Thread.sleep(5.msecs);
                break;
            default: break;
        }
    }

    void damage(Exception ex, string msg = string.init) {
        this.error = ex;
        this.msg(LL.Error, ex, msg);
        this.state = TickerState.Damaged;
    }

    void start() {
        this.state = TickerState.Started;
    }

    void stop() {
        this.state = TickerState.Stopped;
    }

    void tick() {
        if(this.coming !is null) {
            try {
                Tick t = this.coming.create(this);
                if(t !is null) {
                    if(t.info.id == UUID.init)
                        t.info.id = randomUUID;
            
                    if(this.runTick(t) && this.coming !is null) {
                        this.bound.tasker.run(&this.tick);
                        return;
                    } else {
                        if(this.state == TickerState.Started) this.stop();
                        this.msg(LL.FDebug, "nothing to do, ticker ends");
                    }
                } else {
                    throw new TickException("unable to create", this.actual);
                }
            } catch(Exception ex) {
                this.damage(ex, "ticking failed");
            }
        } else {
            if(this.state == TickerState.Started) this.stop();
            this.msg(LL.FDebug, "nothing to do, ticker ends");
        }
    }

    private bool runTick(Tick t) {
        this.ticking = true;
        scope(exit) this.ticking = false;

        // check if entity is still running after getting the sync
        if(this.state == TickerState.Started) {
            this.actual = t.meta;
            this.coming = null;

            try {
                this.msg(LL.FDebug, this.actual, "executing tick");
                t.run();
                this.msg(LL.FDebug, this.actual, "finished tick");
            }
            catch(Exception ex) {
                this.msg(LL.Warning, ex, "tick failed");
                try {
                    this.msg(LL.Info, this.actual, "handling tick error");
                    t.error(ex);
                    this.msg(LL.Info, this.actual, "tick error handled");
                }
                catch(Exception ex2) {
                    this.msg(LL.Warning, ex2, "handling tick error failed");
                }
            }

            return true;
        } else return false;
    }

    void next(TickInfo i, Data d) {
        this.coming = create(i, this.actual, d);
    }

    void fork(TickInfo i, Data d) {
        // TODO create(i, this.actual, d);
        throw new NotImplementedError;
    }
}

private void msg(Ticker t, LL level, string msg) {
    Log.msg(level, "ticker@entity("~t.bound.entity.info.ptr.type~"|"~t.bound.entity.info.ptr.id~"@"~t.bound.entity.info.ptr.flow.id~"): "~msg);
}

private void msg(Ticker t, LL level, Exception ex, string msg = string.init) {
    Log.msg(level, ex, "ticker@entity("~t.bound.entity.info.ptr.type~"|"~t.bound.entity.info.ptr.id~"@"~t.bound.entity.info.ptr.flow.id~"): "~msg);
}

private void msg(Ticker t, LL level, Data d, string msg = string.init) {
    Log.msg(level, d, "ticker@entity("~t.bound.entity.info.ptr.type~"|"~t.bound.entity.info.ptr.id~"@"~t.bound.entity.info.ptr.flow.id~"): "~msg);
}

class Tick {
    package Ticker ticker;
    package TickMeta meta;

    protected @property ReadWriteMutex sync() {return this.ticker.bound.sync;}
    protected @property EntityInfo entity() {return this.ticker.bound.entity.info;}
    protected @property Data context() {return this.ticker.bound.entity.context;}
    protected @property TickInfo info() {return this.meta.info;}
    protected @property Signal trigger() {return this.meta.trigger;}
    protected @property TickInfo previous() {return this.meta.previous;}
    protected @property Data data() {return this.meta.data;}

    public abstract void run();
    public void error(Exception ex) {}

    protected void next(string t, Data d = null) {
        this.ticker.next(this.create(t), d);        
    }

    protected void fork(string t, Data d = null) {
        this.ticker.fork(this.create(t), d);
    }

    protected bool answer(Unicast s) {
        throw new NotImplementedError;
    }

    protected bool send(Unicast s, EntityPtr dst) {
        throw new NotImplementedError;
    }

    protected bool send(Signal s) {
        throw new NotImplementedError;
    }
}

void msg(Tick t, LL level, string msg) {
    Log.msg(level, "tick@entity("~t.ticker.bound.entity.info.ptr.type~"|"~t.ticker.bound.entity.info.ptr.id~"@"~t.ticker.bound.entity.info.ptr.flow.id~"): "~msg);
}

void msg(Tick t, LL level, Exception ex, string msg = string.init) {
    Log.msg(level, ex, "tick@entity("~t.ticker.bound.entity.info.ptr.type~"|"~t.ticker.bound.entity.info.ptr.id~"@"~t.ticker.bound.entity.info.ptr.flow.id~"): "~msg);
}

void msg(Tick t, LL level, Data d, string msg = string.init) {
    Log.msg(level, d, "tick@entity("~t.ticker.bound.entity.info.ptr.type~"|"~t.ticker.bound.entity.info.ptr.id~"@"~t.ticker.bound.entity.info.ptr.flow.id~"): "~msg);
}

private Tick create(TickMeta m, Ticker ticker) {
    auto t = Object.factory(ticker.coming.info.type).as!Tick;
    if(t !is null) {
        t.ticker = ticker;
        t.meta = m;
    }

    return t;
}

private TickInfo create(Tick tick, string t) {
    auto i = new TickInfo;
    i.id = randomUUID;
    i.type = t;
    i.group = tick.info.group;

    return i;
}

private TickMeta create(TickInfo t, Signal s = null) {
    auto m = new TickMeta;
    m.info = t;
    m.trigger = s;

    return m;
}

private TickMeta create(TickInfo t, TickMeta p, Data d = null) {
    auto m = new TickMeta;
    m.info = t;
    m.trigger = p.trigger;
    m.previous = p.info;
    m.data = d;

    return m;
}

version(unittest) {
    import __flow.signal;

    class TestTickException : Exception {this(){super(string.init);}}

    class TestSignal : Signal {
        mixin signalbase;
    }

    class TestTickContext : Data {
        mixin database;

        mixin field!(size_t, "cnt");
        mixin field!(bool, "error");
    }

    class TestTickData : Data {
        mixin database;

        mixin field!(size_t, "cnt");
    }
    
    class TestTick : Tick {
        import __flow.util;

        override void run() {
            auto c = this.context.as!TestTickContext;
            auto d = this.data.as!TestTickData !is null ?
                this.data.as!TestTickData :
                "__flow.tick.TestTickData".data.as!TestTickData;

            d.cnt++;

            if(d.cnt > 3)
                throw new TestTickException;
            
            synchronized(this.sync.writer)
                c.cnt += d.cnt;

            this.next("__flow.tick.TestTick", d);
        }

        override void error(Exception ex) {
            if(ex.as!TestTickException !is null) {
                auto c = this.context.as!TestTickContext;
                c.error = true;
            }
        }
    }
}

unittest {
    import std.stdio;
    writeln("testing ticking");

    auto tasker = new Tasker(1);
    tasker.start();
    scope(exit) tasker.stop();
    auto entity = new EntityInfo;
    entity.ptr = new EntityPtr;
    entity.ptr.id = "testentity";
    entity.ptr.type = "testentitytype";
    entity.ptr.flow = new FlowPtr;
    entity.ptr.flow.id = "testflow";
    auto sync = new ReadWriteMutex(ReadWriteMutex.Policy.PREFER_WRITERS);
    auto c = new TestTickContext;
    auto chan = new OutChannel;
    auto s = new TestSignal;
    auto t1 = new TickInfo;
    t1.id = randomUUID;
    t1.type = "__flow.tick.TestTick";
    t1.group = randomUUID;
    auto ticker1 = new Ticker(bound, entity, sync, c, chan, s, t1);
    ticker1.start();

    while(ticker1.state == TickerState.Started)
        Thread.sleep(5.msecs);

    assert(c.cnt == 6, "logic wasn't executed correct");
    assert(ticker1.actual.trigger.as!TestSignal !is null, "trigger was not passed correctly");
    assert(ticker1.actual.info.group == t1.group, "group was not passed correctly");
    assert(ticker1.actual.data.as!TestTickData !is null, "data was not set correctly");
    assert(ticker1.state == TickerState.Stopped, "ticker was left in wrong state");

    auto t2 = new TickInfo;
    t2.id = randomUUID;
    t2.type = "__flow.tick.TestTickNotExisting";
    t2.group = randomUUID;
    auto ticker2 = new Ticker(exe, entity, sync, c, chan, s, t2);
    ticker2.start();

    while(ticker2.state == TickerState.Started)
        Thread.sleep(5.msecs);

    assert(ticker2.error !is null, "ticker should notify that it could not create tick");
    assert(ticker2.state == TickerState.Damaged, "ticker was left in wrong state");
}