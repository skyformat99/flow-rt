module flow.base.trace;

import std.file, std.conv, std.uuid;

import flow.base.data, flow.base.blocks, flow.base.signals, flow.base.interfaces;

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
        auto c = this.context.as!FileTracerContext;
        auto s = this.signal.as!TraceSend;

        if(c.file !is null && c.file != "")
            append(c.file, "s\t" ~ s.source.type ~ "\t" ~ s.source.id.to!string
                ~ "\t" ~ s.data.type ~ "\t" ~ s.data.id.to!string ~ "\n");
    }
}

class LogTraceReceive : Tick
{
	mixin tick;

	override void run()
	{
        auto c = this.context.as!FileTracerContext;
        auto s = this.signal.as!TraceReceive;

        if(c.file !is null && c.file != "")
            append(c.file, "/s\t" ~ s.source.type ~ "\t" ~ s.source.id.to!string
                ~ "\t" ~ s.data.type ~ "\t" ~ s.data.id.to!string ~ "\n");
    }
}

class LogTraceBeginTick : Tick
{
	mixin tick;

	override void run()
	{
        auto c = this.context.as!FileTracerContext;
        auto s = this.signal.as!TraceBeginTick;

        if(c.file !is null && c.file != "")
            append(c.file, "t\t" ~ s.data.entity.type ~ "\t" ~ s.data.entity.id.to!string
                ~ "\t" ~ s.data.tick ~ "\n");
    }
}

class LogTraceEndTick : Tick
{
	mixin tick;

	override void run()
	{
        auto c = this.context.as!FileTracerContext;
        auto s = this.signal.as!TraceEndTick;

        if(c.file !is null && c.file != "")
            append(c.file, "/t\t" ~ s.data.entity.type ~ "\t" ~ s.data.entity.id.to!string
                ~ "\t" ~ s.data.tick ~ "\n");
    }
}

class FileTracer : Entity, IStealth
{
    mixin entity;

    mixin listen!(fqn!TraceSend, fqn!LogTraceSend);    
    mixin listen!(fqn!TraceReceive, fqn!LogTraceReceive);    
    mixin listen!(fqn!TraceBeginTick, fqn!LogTraceBeginTick);    
    mixin listen!(fqn!TraceEndTick, fqn!LogTraceEndTick);
}