module flow.flow.organ;

import std.uuid;

import flow.base.blocks, flow.base.interfaces;

mixin template TOrgan(T)
    if(is(T : IData))
{
    import flow.base.interfaces;

    shared static this()
    {
        Organ.register(fqn!T, (config){
            auto c = config.as!T;
            return new typeof(this)(c);
        });
    }

    override @property string __fqn() {return fqn!(typeof(this));}

    @property T tconfig(){return this.context.as!T;}

    this(T config)
    {
        this._config = config;
    }
}

abstract class Organ : IOrgan
{
    private static IOrgan function(IData)[string] _reg;
    
    static void register(string dataType, IOrgan function(IData) creator)
	{
        _reg[dataType] = creator;
	}

	static bool can(IData config)
	{
		return config !is null && config.dataType in _reg ? true : false;
	}

	static IOrgan create(IData config)
	{
		if(config !is null && config.dataType in _reg)
			return _reg[config.dataType](config);
		else
			return null;
	}
    
    abstract @property string __fqn();
    private UUID _id;
    @property UUID id() {return this._id;}
    private IHull _hull;
    @property IHull hull() {return this._hull;}
    @property void hull(IHull value) {this._hull = value;}

    protected IData _config;
    @property IData config() {return this._config;}

    protected IData _context;
    @property IData context() {return this._context;}

    this(UUID id = randomUUID) { this._id = id;}

    void create()
    {
        this._context = this.start();
    }

    void dispose()
    {
        this.stop();
    }

    abstract IData start();
    abstract void stop();

    @property bool finished(){return true;}
}