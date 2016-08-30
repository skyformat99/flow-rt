module flow.util.trace;

import std.file, std.conv;

import flow.blocks, flow.signals, flow.interfaces;

class FileTracerContext : Data
{
	mixin data;

    mixin field!(string, "file");
}

class LogTraceSend : Tick
{
	mixin tick;

	override void run()
	{
        auto c = this.entity.context.as!FileTracerContext;
        auto s = this.trigger.as!TraceSend;

        if(c.file !is null && c.file != "")
            append(c.file, "s\t" ~ s.source.type ~ "\t" ~ s.source.id.toString
                ~ "\t" ~ s.data.type ~ "\t" ~ s.data.id.toString ~ "\n");
    }
}

class LogTraceReceive : Tick
{
	mixin tick;

	override void run()
	{
        auto c = this.entity.context.as!FileTracerContext;
        auto s = this.trigger.as!TraceReceive;

        if(c.file !is null && c.file != "")
            append(c.file, "/s\t" ~ s.source.type ~ "\t" ~ s.source.id.toString
                ~ "\t" ~ s.data.type ~ "\t" ~ s.data.id.toString ~ "\n");
    }
}

class LogTraceBeginTick : Tick
{
	mixin tick;

	override void run()
	{
        auto c = this.entity.context.as!FileTracerContext;
        auto s = this.trigger.as!TraceBeginTick;

        if(c.file !is null && c.file != "")
            append(c.file, "t\t" ~ s.data.entityType ~ "\t" ~ s.data.entityId.to!string
                ~ "\t" ~ s.data.ticker.to!string ~ "\t" ~ s.data.seq.to!string ~ "\t" ~ s.data.tick ~ "\n");
    }
}

class LogTraceEndTick : Tick
{
	mixin tick;

	override void run()
	{
        auto c = this.entity.context.as!FileTracerContext;
        auto s = this.trigger.as!TraceEndTick;

        if(c.file !is null && c.file != "")
            append(c.file, "/t\t" ~ s.data.entityType ~ "\t" ~ s.data.entityId.to!string
                ~ "\t" ~ s.data.ticker.to!string ~ "\t" ~ s.data.seq.to!string ~ "\t" ~ s.data.tick ~ "\n");
    }
}

class FileTracer : Entity, IStealth
{
    mixin entity!(FileTracerContext);

    mixin listen!(fqn!TraceSend,
        (e, s) => new LogTraceSend
    );
    
    mixin listen!(fqn!TraceReceive,
        (e, s) => new LogTraceReceive
    );
    
    mixin listen!(fqn!TraceBeginTick,
        (e, s) => new LogTraceBeginTick
    );
    
    mixin listen!(fqn!TraceEndTick,
        (e, s) => new LogTraceEndTick
    );
}