module flow.ticks;

import flow.base.tick, flow.base.entity, flow.base.type;
import flow.signals, flow.interfaces;

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