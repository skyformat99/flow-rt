module flow.signals;

import std.uuid;

import flow.base.data, flow.base.signal;
import flow.data, flow.interfaces;

class Ping : Multicast, IStealth
{
    mixin TSignal!(EntityInfo);
}
class UPing : Unicast, IStealth
{
    mixin TSignal!(EntityInfo);
}
class Pong : Unicast, IStealth
{
    mixin TSignal!(EntityInfo);
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