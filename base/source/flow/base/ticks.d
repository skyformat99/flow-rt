module flow.base.ticks;

import __flow.tick, __flow.entity, __flow.type;
import flow.base.signals, flow.base.interfaces;

class SendPong : Tick, IStealth
{
    mixin TTick;

    override void run()
    {
        this.entity.as!Entity.writeDebug("received ping from entity("~this.trigger.source.type~", "~this.trigger.source.id.toString~")", 2);
        auto p = new Pong;
        p.data = this.entity.info;
        this.answer(p);
    }
}