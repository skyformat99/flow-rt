module flow.base.ticks;

import __flow.ticker, __flow.entity, __flow.type;
import flow.base.signals, flow.base.interfaces, flow.base.data, flow.base.dev;

class SendPong : Tick, IStealth
{
    mixin TTick;

    override void run() {
        this.msg(DL.Debug, this.signal.source, "received ping from entity");
        auto p = new Pong;
        p.ptr = this.entity.ptr;
        p.signals.put(this.entity.signals);
        this.answer(p);
    }
}