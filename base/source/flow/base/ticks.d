module flow.base.ticks;

import __flow.tick, __flow.entity, __flow.type;
import flow.base.signals, flow.base.interfaces, flow.base.data;

class SendPong : Tick, IStealth
{
    mixin TTick;

    override void run() {
        this.writeDebug("received ping from entity("~this.signal.source.type~"|"~this.signal.source.id~"@"~this.signal.source.domain~")", 2);
        auto p = new Pong;
        p.ptr = this.entity.ptr;
        p.signals.put(this.entity.signals);
        this.answer(p);
    }
}