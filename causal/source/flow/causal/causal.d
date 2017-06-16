module flow.causal.causal;

import std.uuid;

import flow.base.blocks;
import flow.data.memory;
import flow.alien.nls.ad.cl;

class CausalConfig : Data
{
	mixin data;

    mixin field!(string, "descriptionMemoryUrl");
    mixin field!(MemoryFormat, "descriptionMemoryFormat");
}

class CausalContext : Data
{
	mixin data;

    mixin field!(UUID, "memory");
    mixin field!(UUID, "nls");
}

class Causal : Organ
{
    mixin organ!(CausalConfig);

    override IData start()
    {
        import std.file;

        auto c = new CausalContext;
        auto conf = config.as!CausalConfig;

        if(!conf.descriptionMemoryUrl.exists)
            conf.descriptionMemoryUrl.mkdirRecurse();

        auto memorySettings = new FileMemorySettings;
        memorySettings.url = conf.descriptionMemoryUrl;
        memorySettings.format = conf.descriptionMemoryFormat;
        memorySettings.types.put(fqn!Description);

        auto memoryContext = new MemoryContext;
        auto memory = new Memory(memoryContext, memorySettings);
        memory.storage = new FileMemoryStorage(memory);
        c.memory = this.hull.add(memory);

        c.nls = this.hull.add(new ClAdNls);

        return c;
    }

    override void stop()
    {
        auto c = context.as!CausalContext;

        this.hull.remove(c.nls);
        this.hull.remove(c.memory);
    }
}