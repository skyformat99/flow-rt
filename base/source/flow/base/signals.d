module flow.base.signals;

import std.uuid;

import __flow.data, __flow.signal;
import flow.base.interfaces, flow.base.data;

static import flow.base.data;
alias Signal = flow.base.data.Signal;

class Unicast : Signal
{
    mixin TSignal;

    mixin TField!(EntityPtr, "destination");
}

class Multicast : Signal
{
    mixin TSignal;

    mixin TField!(string, "domain");
}

class Anycast : Signal
{    
    mixin TSignal;

    mixin TField!(string, "domain");
}

class Ping : Multicast, IStealth
{
    mixin TSignal;
}
class UPing : Unicast, IStealth
{
    mixin TSignal;
}
class Pong : Unicast, IStealth
{
    mixin TSignal;

    mixin TField!(EntityPtr, "ptr");
    mixin TList!(string, "signals");
}

class TraceSend : Multicast, IStealth
{
    mixin TSignal!(TraceSignalData);
}

class TraceReceive : Multicast, IStealth
{
    mixin TSignal!(TraceSignalData);
}

class TraceBeginTick : Multicast, IStealth
{
    mixin TSignal!(TraceTickData);
}

class TraceEndTick : Multicast, IStealth
{
    mixin TSignal!(TraceTickData);
}

class WrappedSignal : Unicast, IStealth {mixin TSignal;}